#!/bin/bash

proxy_env_file="/etc/redsocks_proxy_env"
default_parameter="all"

# 参数提示函数
show_help() {
    echo "Usage: $0 {all|none|gflist}"
}

# 检查参数是否为帮助提示
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 设置默认参数
if [ -z "$1" ]; then
    if [ -f "$proxy_env_file" ]; then
        source "$proxy_env_file"
        parameter=${parameter:-$default_parameter}
    else
        parameter=$default_parameter
    fi
else
    parameter=$1
    # 保存参数到配置文件
    echo "parameter=\"$parameter\"" > "$proxy_env_file"
fi

# 清理 iptables
iptables -t nat -F

# 设置不需要代理的规则
set_no_proxy() {
    while read -r line; do
        echo -e "\033[32m this ip[${line}] will no connected .... \033[0m"
        ${SUDO} iptables -t nat -A OUTPUT -p tcp -d "$line" -j RETURN
    done </etc/NoProxy.txt
}

# 设置默认代理规则
set_default_proxy() {
    for i in $(ip route show | awk '{print $1}' | grep -v default); do
        iptables -t nat -A OUTPUT -p tcp -d "$i" -j RETURN
    done
    set_no_proxy
    iptables -t nat -A OUTPUT -p tcp -d SED_SOCK_SERVER -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
}

# 获取脚本参数
case "$parameter" in
    "all")
        echo "Running the 'all' branch"
        set_default_proxy
        iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports SED_PROXY_PORT
        ;;
    "none")
        echo "Running the 'none' branch"
        # 在此处添加 'none' 参数对应的操作逻辑
        ;;
    "gflist")
        echo "Running the 'gflist' branch"
        set_default_proxy
        while read -r line; do
            echo -e "\033[32m this ip[${line}] will use proxy connected .... \033[0m"
            iptables -t nat -A OUTPUT -p tcp -d "$line" -j REDIRECT --to-ports SED_PROXY_PORT
        done </etc/GFlist.txt
        ;;
    *)
        echo "Invalid input. Usage: $0 {all|none|gflist}"
        exit 1
        ;;
esac

echo -e "\033[32m your iptables OUTPUT chain like this.... \033[0m"
iptables -t nat -nvL --line-numbers
