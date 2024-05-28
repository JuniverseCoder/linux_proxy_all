#!/bin/bash
set -e

# 获取脚本所在目录，即使当前文件被软链接到其他文件
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# 定义项目根目录
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# 定义目录
CONF_DIR="${PROJECT_ROOT}/conf"

PROXY_CONF_FILE="${CONF_DIR}/tcp_proxy.conf"
DEFAULT_PROXY_TYPE="all"

# 参数提示函数
show_help() {
    echo "Usage: $0 {all|none|rule}"
}

# 检查参数是否为帮助提示
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 检查 PROXY_CONF_FILE 是否存在
if [[ ! -f "$PROXY_CONF_FILE" ]]; then
    echo "Error: $PROXY_CONF_FILE does not exist."
    exit 1
fi

# 加载配置文件
source "$PROXY_CONF_FILE"

# 函数用于更新配置文件中的指定键值对
update_conf() {
    local KEY=$1
    local VALUE=$2
    if grep -q "^$KEY=" "$PROXY_CONF_FILE"; then
        sed -i "s/^$KEY=.*/$KEY=\"$VALUE\"/" "$PROXY_CONF_FILE"
    else
        echo "$KEY=\"$VALUE\"" >> "$PROXY_CONF_FILE"
    fi
}

# 检查是否设置了 PROXY_PORT 和 SOCK_SERVER
if [[ -z "$PROXY_PORT" || -z "$SOCK_SERVER" ]]; then
    echo "Error: PROXY_PORT and SOCK_SERVER must be set in $PROXY_CONF_FILE."
    exit 1
fi

# 设置默认参数
if [ -z "$1" ]; then
    PROXY_TYPE=${PROXY_TYPE:-$DEFAULT_PROXY_TYPE}
else
    PROXY_TYPE=$1
    # 保存参数到配置文件，保留其他变量
    update_conf "PROXY_TYPE" "$PROXY_TYPE"
fi

# 清理 iptables
iptables -t nat -F

# 设置不需要代理的规则
set_no_proxy() {
    while read -r LINE; do
        echo -e "\033[32m this ip[${LINE}] will not be connected .... \033[0m"
        iptables -t nat -A OUTPUT -p tcp -d "$LINE" -j RETURN
    done < "${CONF_DIR}/no_proxy.conf"
}

# 设置默认代理规则
set_default_proxy() {
    for I in $(ip route show | awk '{print $1}' | grep -v default); do
        iptables -t nat -A OUTPUT -p tcp -d "$I" -j RETURN
    done
    set_no_proxy
    iptables -t nat -A OUTPUT -p tcp -d "$SOCK_SERVER" -j RETURN
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 -j RETURN
}

# 获取脚本参数
case "$PROXY_TYPE" in
    "all")
        echo "Running the 'all' branch"
        set_default_proxy
        iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports "$PROXY_PORT"
        ;;
    "none")
        echo "Running the 'none' branch"
        # 在此处添加 'none' 参数对应的操作逻辑
        ;;
    "rule")
        echo "Running the 'rule' branch"
        set_default_proxy
        while read -r LINE; do
            echo -e "\033[32m this ip[${LINE}] will use proxy connected .... \033[0m"
            iptables -t nat -A OUTPUT -p tcp -d "$LINE" -j REDIRECT --to-ports "$PROXY_PORT"
        done < "${CONF_DIR}/proxy.conf"
        ;;
    *)
        echo "Invalid input. Usage: $0 {all|none|rule}"
        exit 1
        ;;
esac

echo -e "\033[32m your iptables OUTPUT chain like this.... \033[0m"
iptables -t nat -nvL --line-numbers
