#!/bin/sh

# 检查环境依赖
[ -z "$CURL_SSL" ] && write_log 14 "Require cURL with SSL. Please install 'curl' and 'ca-bundle'."
[ -z "$username" ] && write_log 14 "Missing 'username' (Use 'Bearer' for Token mode)"
[ -z "$password" ] && write_log 14 "Missing 'password' (Your API Token/Key)"

local __URLBASE __PRGBASE __RUNPROG __TYPE __DOM_LIST
__URLBASE="https://api.cloudflare.com/client/v4"

# 1. 核心改进：合并主域名和可选参数里的额外域名
# 插件会将“可选参数”框里的内容赋值给 $param_opt
# 我们将逗号替换为空格，合并成一个标准的循环列表
__DOM_LIST=$(echo "$domain $param_opt" | tr ',' ' ')

# 2. 判定记录类型
[ $use_ipv6 -eq 0 ] && __TYPE="A" || __TYPE="AAAA"

cloudflare_transfer() {
    local __ERR
    eval "$__RUNPROG"
    __ERR=$?
    [ $__ERR -ne 0 ] && { write_log 3 "cURL Error: $__ERR"; return 1; }
    grep -q '"success":true' $DATFILE || { write_log 4 "CF Error: $(cat $DATFILE)"; return 1; }
    return 0
}

# 3. 构造基础命令
__PRGBASE="$CURL -RsS -o $DATFILE --stderr $ERRFILE --header 'Content-Type: application/json'"
if [ "$username" = "Bearer" ]; then
    __PRGBASE="$__PRGBASE --header 'Authorization: Bearer $password'"
else
    __PRGBASE="$__PRGBASE --header 'X-Auth-Email: $username' --header 'X-Auth-Key: $password'"
fi

# 4. 循环处理所有域名
for __ENTRY in $__DOM_LIST; do
    local __HOST __DOMAIN __ZONEID __RECID
    
    # 解析 host@domain.com
    __HOST=$(printf %s "$__ENTRY" | cut -d@ -f1)
    __DOMAIN=$(printf %s "$__ENTRY" | cut -d@ -f2)
    [ -z "$__HOST" ] && __HOST=$__DOMAIN
    [ "$__HOST" != "$__DOMAIN" ] && __HOST="${__HOST}.${__DOMAIN}"

    write_log 7 "Smart-Update: Working on $__HOST ($__TYPE)"

    # A. 获取 Zone ID
    __RUNPROG="$__PRGBASE --request GET '$__URLBASE/zones?name=$__DOMAIN'"
    cloudflare_transfer || continue
    __ZONEID=$(grep -o '"id":"[^"]*' $DATFILE | grep -o '[^"]*$' | head -1)

    # B. 获取 Record ID
    __RUNPROG="$__PRGBASE --request GET '$__URLBASE/zones/$__ZONEID/dns_records?name=$__HOST&type=$__TYPE'"
    cloudflare_transfer || continue
    __RECID=$(grep -o '"id":"[^"]*' $DATFILE | grep -o '[^"]*$' | head -1)

    # C. 执行 更新 或 创建
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
