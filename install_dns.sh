#!/bin/bash
set -e

# 获取脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 从dnsserverinfo文件中读取$PROXY_DNS_PORT和DEFAULT_NAMESERVER，如果文件不存在则使用默认值
if [[ -f dnsserverinfo ]]; then
    source dnsserverinfo
else
    # 用户输入PROXY_DNS_PORT和DEFAULT_NAMESERVER
    read -p "Please enter PROXY_DNS_PORT (default: 5300): " PROXY_DNS_PORT
    PROXY_DNS_PORT=${PROXY_DNS_PORT:-5300}
    DEFAULT_NAMESERVER=$(awk '/nameserver/ && !/^#/{print $2; exit}' /etc/resolv.conf)
    read -p "Please enter DEFAULT_NAMESERVER (default: $DEFAULT_NAMESERVER): " custom_nameserver
    DEFAULT_NAMESERVER=${custom_nameserver:-$DEFAULT_NAMESERVER}
    # 保存输入值到dnsserverinfo文件
    echo "PROXY_DNS_PORT=$PROXY_DNS_PORT" > dnsserverinfo
    echo "DEFAULT_NAMESERVER=$DEFAULT_NAMESERVER" >> dnsserverinfo
fi

update_pdnsd_config(){
    cat default_pdnsd.example > /etc/default/pdnsd
    cat pdnsd.conf.example > /etc/pdnsd.conf
    sed -i "s|\${PROXY_DNS_PORT}|$PROXY_DNS_PORT|g" /etc/pdnsd.conf
}

# 检查pdnsd服务是否已经存在
if ! command -v  pdnsd &>/dev/null; then
    # 如果服务不存在，执行安装和配置
    echo "pdnsd service does not exist, installing and configuring..."

    # 检查端口是否已经被占用
    if netstat -tuln | grep ":$PROXY_DNS_PORT " >/dev/null; then
        echo "Error: Port $PROXY_DNS_PORT is already in use."
        exit 1
    fi

    # 安装pdnsd
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        case $ID in
            debian|ubuntu)
                # 安装pdnsd on Debian/Ubuntu
                arch=$(dpkg --print-architecture)
                package_name="pdnsd_1.2.9a-par-3"
                deb_file="${package_name}_${arch}.deb"

                echo "Installing $deb_file"
                dpkg -i "$deb_file"
                ;;
            fedora|centos|rhel)
                # 安装pdnsd on Fedora/CentOS/RHEL
                arch=$(uname -m)
                package_name="pdnsd-1.2.9a-par"
                rpm_file="${package_name}.${arch}.rpm"

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

# 定义函数来处理DNS规则配置
configure_dns_rules() {
    # 初始化SERVER_RULES变量为空字符串
    SERVER_RULES=""

    # 读取proxy_dns.txt文件的每一行
    while IFS= read -r line; do
        # 去除前后的空白
        trimmed_line="$(echo -e "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # 如果行不为空，则添加server规则到SERVER_RULES变量
        if [ -n "$trimmed_line" ]; then
            SERVER_RULES+="server=/$trimmed_line/127.0.0.1#$PROXY_DNS_PORT\n"
        fi
    done < "proxy_dns.txt"

    # 拷贝dnsmasq.conf.example文件到/etc/dnsmasq.conf
    cp "${SCRIPT_DIR}/dnsmasq.conf.example" /etc/dnsmasq.conf

    # 替换文件中的${SERVER_RULES}和${DEFAULT_NAMESERVER}
    sed -i "s|\${SERVER_RULES}|$SERVER_RULES|g" /etc/dnsmasq.conf
    sed -i "s|\${DEFAULT_NAMESERVER}|$DEFAULT_NAMESERVER|g" /etc/dnsmasq.conf
}

# 检查dnsmasq服务是否已经存在
if ! command -v dnsmasq &>/dev/null; then
    # 如果服务不存在，执行安装和配置
    echo "dnsmasq service does not exist, installing and configuring..."
    # 安装dnsmasq
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

    # 配置dnsmasq服务自动启动
    if [[ $(ps -p 1 -o comm=) == "systemd" ]]; then
        # Systemd 系统
        systemctl enable dnsmasq
    else
        # SysV Init 系统
        chkconfig dnsmasq on
    fi

    # 询问是否修改/etc/resolv.conf的nameserver为127.0.0.1
    read -p "Do you want to set nameserver in /etc/resolv.conf to 127.0.0.1? (y/n): " set_nameserver
    if [ "$set_nameserver" == "y" ]; then
        echo "nameserver 127.0.0.1" > /etc/resolv.conf
        # 锁定/etc/resolv.conf文件
        chattr +i /etc/resolv.conf
        echo "nameserver in /etc/resolv.conf set to 127.0.0.1 and locked."
    else
        echo "nameserver in /etc/resolv.conf remains unchanged."
    fi
    
else
    # 如果服务已存在，只更新配置文件
    echo "dnsmasq service already exists, updating configuration..."
fi

# 调用函数来配置DNS规则
configure_dns_rules

# 重启更新dnsmasq配置文件的
if [[ $(ps -p 1 -o comm=) == "systemd" ]]; then
    # Systemd 系统
    systemctl restart dnsmasq
else
    # SysV Init 系统
    service dnsmasq restart
fi

