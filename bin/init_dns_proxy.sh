#!/bin/bash
set -e

# 获取脚本所在目录，即使当前文件被软链接到其他文件
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# 定义项目根目录
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# Define directories
CONF_DIR="${PROJECT_ROOT}/conf"
INSTALL_DIR="${PROJECT_ROOT}/install"

DNS_PROXY_CONF="${CONF_DIR}/dns_proxy.conf"

# 从 dns_proxy.conf 文件中读取 $PROXY_DNS_PORT 和 $DEFAULT_NAMESERVER，如果文件不存在则使用默认值
if [[ -f "$DNS_PROXY_CONF" ]]; then
    source "$DNS_PROXY_CONF"
else
    # 用户输入 PROXY_DNS_PORT 和 DEFAULT_NAMESERVER
    read -p "Please enter PROXY_DNS_PORT (default: 5300): " PROXY_DNS_PORT
    PROXY_DNS_PORT=${PROXY_DNS_PORT:-5300}
    DEFAULT_NAMESERVER=$(awk '/nameserver/ && !/^#/{print $2; exit}' /etc/resolv.conf)
    read -p "Please enter DEFAULT_NAMESERVER (default: $DEFAULT_NAMESERVER): " custom_nameserver
    DEFAULT_NAMESERVER=${custom_nameserver:-$DEFAULT_NAMESERVER}
    # 保存输入值到 dns_proxy.conf 文件
    echo "PROXY_DNS_PORT=$PROXY_DNS_PORT" > "$DNS_PROXY_CONF"
    echo "DEFAULT_NAMESERVER=$DEFAULT_NAMESERVER" >> "$DNS_PROXY_CONF"
fi

update_pdnsd_config(){
    cp "${INSTALL_DIR}/default_pdnsd.example" /etc/default/pdnsd
    cp "${INSTALL_DIR}/pdnsd.conf.example" /etc/pdnsd.conf
    sed -i "s|\${PROXY_DNS_PORT}|$PROXY_DNS_PORT|g" /etc/pdnsd.conf
}

# 检查 pdnsd 服务是否已经存在
if ! command -v pdnsd &>/dev/null; then
    # 如果服务不存在，执行安装和配置
    echo "pdnsd service does not exist, installing and configuring..."

    # 检查端口是否已经被占用
    if netstat -tuln | grep ":$PROXY_DNS_PORT " >/dev/null; then
        echo "Error: Port $PROXY_DNS_PORT is already in use."
        exit 1
    fi

    # 安装 pdnsd
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        case $ID in
            debian|ubuntu)
                # 安装 pdnsd on Debian/Ubuntu
                arch=$(dpkg --print-architecture)
                package_name="pdnsd_1.2.9a-par-3"
                deb_file="${INSTALL_DIR}/${package_name}_${arch}.deb"

                echo "Installing $deb_file"
                dpkg -i "$deb_file"
                ;;
            fedora|centos|rhel)
                # 安装 pdnsd on Fedora/CentOS/RHEL
                arch=$(uname -m)
                package_name="pdnsd-1.2.9a-par"
                rpm_file="${INSTALL_DIR}/${package_name}.${arch}.rpm"

                echo "Installing $rpm_file"
                rpm -i "$rpm_file"
                ;;
            *)
                echo "Unsupported distribution: $ID"
                exit 1
                ;;
        esac
    else
        echo "Unable to determine the operating system."
        exit 1
    fi
else
    # 如果服务已存在，只更新配置文件
    echo "pdnsd service already exists, updating configuration..."
fi

update_pdnsd_config
if [[ $(ps -p 1 -o comm=) == "systemd" ]]; then
    # Systemd 系统
    systemctl restart pdnsd
else
    # SysV Init 系统
    service pdnsd restart
fi

# 定义函数来处理 DNS 规则配置
configure_dns_rules() {
    # 初始化 SERVER_RULES 变量为空字符串
    SERVER_RULES=""

    # 读取 dns_rule.conf 文件的每一行
    while IFS= read -r line; do
        # 去除前后的空白
        trimmed_line="$(echo -e "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # 如果行不为空，则添加 server 规则到 SERVER_RULES 变量
        if [ -n "$trimmed_line" ]; then
            SERVER_RULES+="server=/$trimmed_line/127.0.0.1#$PROXY_DNS_PORT\n"
        fi
    done < "${CONF_DIR}/dns_rule.conf"

    # 拷贝 dnsmasq.conf.example 文件到 /etc/dnsmasq.conf
    cp "${INSTALL_DIR}/dnsmasq.conf.example" /etc/dnsmasq.conf

    # 替换文件中的 ${SERVER_RULES} 和 ${DEFAULT_NAMESERVER}
    sed -i "s|\${SERVER_RULES}|$SERVER_RULES|g" /etc/dnsmasq.conf
    sed -i "s|\${DEFAULT_NAMESERVER}|$DEFAULT_NAMESERVER|g" /etc/dnsmasq.conf
}

# 检查 dnsmasq 服务是否已经存在
if ! command -v dnsmasq &>/dev/null; then
    # 如果服务不存在，执行安装和配置
    echo "dnsmasq service does not exist, installing and configuring..."
    # 安装 dnsmasq
    if [ -f /etc/redhat-release ]; then
        yum update -y
        yum install -y dnsmasq
    elif [ -f /etc/lsb-release ]; then
        apt-get update
        apt-get install -y dnsmasq
    else
        echo "Unsupported Linux distribution"
        exit 1
    fi

    # 启用或禁用相应的服务
    if service systemd-resolved status >/dev/null 2>&1; then
        service systemd-resolved stop
        systemctl disable systemd-resolved
    fi

    # 配置 dnsmasq 服务自动启动
    if [[ $(ps -p 1 -o comm=) == "systemd" ]]; then
        # Systemd 系统
        systemctl enable dnsmasq
    else
        # SysV Init 系统
        chkconfig dnsmasq on
    fi

    # 询问是否修改 /etc/resolv.conf 的 nameserver 为 127.0.0.1
    read -p "Do you want to set nameserver in /etc/resolv.conf to 127.0.0.1? (y/n): " set_nameserver
    if [ "$set_nameserver" == "y" ]; then
        echo "nameserver 127.0.0.1" > /etc/resolv.conf
        # 锁定 /etc/resolv.conf 文件
        chattr +i /etc/resolv.conf
        echo "nameserver in /etc/resolv.conf set to 127.0.0.1 and locked."
    else
        echo "nameserver in /etc/resolv.conf remains unchanged."
    fi

else
    # 如果服务已存在，只更新配置文件
    echo "dnsmasq service already exists, updating configuration..."
fi

# 调用函数来配置 DNS 规则
configure_dns_rules

# 重启更新 dnsmasq 配置文件的服务
if [[ $(ps -p 1 -o comm=) == "systemd" ]]; then
    # Systemd 系统
    systemctl restart dnsmasq
else
    # SysV Init 系统
    service dnsmasq restart
fi
