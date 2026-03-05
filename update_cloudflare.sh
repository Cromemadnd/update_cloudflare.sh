#!/bin/sh

[ -z "$CURL_SSL" ] && write_log 14 "Require cURL with SSL. Please install 'curl' and 'ca-bundle'."
[ -z "$username" ] && write_log 14 "Missing 'username' (Use 'Bearer' for Token mode)"
[ -z "$password" ] && write_log 14 "Missing 'password' (Your API Token/Key)"

local __URLBASE __PRGBASE __RUNPROG __TYPE __DOM_LIST
__URLBASE="https://api.cloudflare.com/client/v4"

__DOM_LIST=$(echo "$domain $param_opt" | tr ',' ' ')

[ $use_ipv6 -eq 0 ] && __TYPE="A" || __TYPE="AAAA"

cloudflare_transfer() {
    local __ERR
    eval "$__RUNPROG"
    __ERR=$?
    [ $__ERR -ne 0 ] && { write_log 3 "cURL Error: $__ERR"; return 1; }
    grep -q '"success":true' $DATFILE || { write_log 4 "CF Error: $(cat $DATFILE)"; return 1; }
    return 0
}

__PRGBASE="$CURL -RsS -o $DATFILE --stderr $ERRFILE --header 'Content-Type: application/json'"
if [ "$username" = "Bearer" ]; then
    __PRGBASE="$__PRGBASE --header 'Authorization: Bearer $password'"
else
    __PRGBASE="$__PRGBASE --header 'X-Auth-Email: $username' --header 'X-Auth-Key: $password'"
fi

for __ENTRY in $__DOM_LIST; do
    local __HOST __DOMAIN __ZONEID __RECID
    
    # Resolve host@domain.com
    __HOST=$(printf %s "$__ENTRY" | cut -d@ -f1)
    __DOMAIN=$(printf %s "$__ENTRY" | cut -d@ -f2)
    [ -z "$__HOST" ] && __HOST=$__DOMAIN
    [ "$__HOST" != "$__DOMAIN" ] && __HOST="${__HOST}.${__DOMAIN}"

    write_log 7 "Smart-Update: Working on $__HOST ($__TYPE)"

    # A. Get Zone ID
    __RUNPROG="$__PRGBASE --request GET '$__URLBASE/zones?name=$__DOMAIN'"
    cloudflare_transfer || continue
    __ZONEID=$(grep -o '"id":"[^"]*' $DATFILE | grep -o '[^"]*$' | head -1)

    # B. Get Record ID
    __RUNPROG="$__PRGBASE --request GET '$__URLBASE/zones/$__ZONEID/dns_records?name=$__HOST&type=$__TYPE'"
    cloudflare_transfer || continue
    __RECID=$(grep -o '"id":"[^"]*' $DATFILE | grep -o '[^"]*$' | head -1)

    # C. Run update / create
    if [ -n "$__RECID" ]; then
        __RUNPROG="$__PRGBASE --request PUT --data '{\"type\":\"$__TYPE\",\"name\":\"$__HOST\",\"content\":\"$__IP\",\"ttl\":60}' '$__URLBASE/zones/$__ZONEID/dns_records/$__RECID'"
    else
        __RUNPROG="$__PRGBASE --request POST --data '{\"type\":\"$__TYPE\",\"name\":\"$__HOST\",\"content\":\"$__IP\",\"ttl\":60}' '$__URLBASE/zones/$__ZONEID/dns_records'"
    fi

    if cloudflare_transfer; then
        write_log 6 "Smart-Update Success: $__HOST [$__TYPE] -> $__IP"
    else
        write_log 4 "Smart-Update Failed: $__HOST"
    fi
done

return 0
