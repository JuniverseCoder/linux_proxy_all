#!/bin/bash

# 定义项目根目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# 定义dnsserverinfo文件路径
DNS_SERVER_INFO="${PROJECT_ROOT}/conf/dns_proxy.conf"

# 函数用于打印并执行命令
run_command() {
    echo "Running: $*"
    eval "$@"
}

echo "### 1. 检查使用 TCP 查找 8.8.8.8 是否成功"
run_command "dig +tcp @8.8.8.8 github.com"
if [[ $? -ne 0 ]]; then
    echo "TCP 查找 8.8.8.8 失败，检查 redsocks 是否工作正常"
    # 检查 redsocks 状态（假设服务名为 redsocks）
    run_command "service redsocks status"
fi

echo "### 2. 检查 pdnsd 状态"
run_command "dig @127.0.0.1 -p 5300 github.com"
if [[ $? -ne 0 ]]; then
    echo "pdnsd 查找失败，检查 pdnsd 是否正常运行"
    run_command "service pdnsd status"
    if [[ $? -ne 0 ]]; then
        echo "pdnsd 未运行，启动 pdnsd"
        run_command "service pdnsd start"
    fi
fi

echo "### 3. 检查默认代理状态"
if [[ -f "$DNS_SERVER_INFO" ]]; then
    source "$DNS_SERVER_INFO"
    if [[ -z "$DEFAULT_NAMESERVER" ]]; then
        echo "默认代理IP未在 dnsserverinfo 文件中设置"
        exit 1
    fi
else
    echo "dnsserverinfo 文件不存在"
    exit 1
fi

run_command "dig @${DEFAULT_NAMESERVER} github.com"
if [[ $? -ne 0 ]]; then
    echo "默认代理查找失败，检查默认代理IP是否正确，修改 dnsserverinfo 中的 DEFAULT_NAMESERVER，然后重新运行 bin/install_dns.sh 来更新配置"
    exit 1
fi

echo "### 4. 检查 dnsmasq 状态"
run_command "dig @127.0.0.1 github.com"
if [[ $? -ne 0 ]]; then
    echo "dnsmasq 查找失败，检查 dnsmasq 是否正常运行"
    run_command "service dnsmasq status"
    if [[ $? -ne 0 ]]; then
        echo "dnsmasq 未运行，启动 dnsmasq"
        run_command "service dnsmasq start"
    fi
fi

echo "### 5. 检查 /etc/resolv.conf"
run_command "cat /etc/resolv.conf"
if ! grep -q "nameserver 127.0.0.1" /etc/resolv.conf; then
    echo "/etc/resolv.conf 中 nameserver 未设置为 127.0.0.1，请手动修改"
    exit 1
fi

echo "### 6. 检查全流程是否成功"
run_command "dig github.com"
if [[ $? -eq 0 ]]; then
    echo "DNS 解析成功"
else
    echo "DNS 解析失败"
fi
