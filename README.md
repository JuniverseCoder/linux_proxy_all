# 简介

本项目实现了在 Linux 系统下的全局Socket5代理方案，其中包括两部分：

1. **使用 redsocks 配合 iptables 代理 TCP 连接：**

   此部分使用 iptables 将指定的 TCP 连接代理到 redsocks，然后使用 redsocks 将流量转发到配置的 Socket5 代理服务器上。

2. **使用 dnsmasq 和 pdnsd 代理 DNS 请求：**

   此部分配置了 dnsmasq 和 pdnsd，以代理系统的 DNS 请求。dnsmasq 将本地的 DNS 请求转发给 pdnsd，而 pdnsd 将 DNS 请求发送到 Socket5 代理服务器。整个 DNS 请求流程如下所示：

   本地应用程序 (resolv.conf) <-------> dnsmasq:53 (UDP) <-------> pdnsd:5300 (TCP) <-------> redsocks <-------> Socket5 代理服务器

# 使用 redsocks 配合 iptables 代理 TCP 连接

为了方便使用，我们提供了一个针对 `redsocks` 的预编译版本，无需手动安装依赖，可用于 x86 和 aarch64 架构的系统。以下是使用方法：

## 安装

```bash
Shell> git clone 本仓库
Shell> ./install_redsocks.sh
please tell me your sock_server (default: 127.0.0.1): # 输入 Socket5代理服务器的地址（默认为 127.0.0.1）
please tell me your sock_port (default: 7070):        # 输入 Socket5代理服务器的端口（默认为 7070）
Please tell me your proxy_port (default: 12345):      # 输入 Redsock的监听端口（默认为 12345）
```

## 启动 redsocks

```bash
Shell > service redsocks start
```

## 选择代理模式

**全局代理模式**

```bash
Shell> proxy all      # 启动全局代理模式，此模式下将代理所有的访问

 your iptables OUTPUT chain like this....
 Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination

 Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination

 Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination
 1        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.188.0/24
 2        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1
 3        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1
 4        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            redir ports 12345

 Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
 num   pkts bytes target     prot opt in     out     source               destination
```

**代理指定主机**

此模式下仅代理 `GFlist.txt` 中指定的主机。

```bash
Shell> proxy gflist

this ip[216.58.194.99] will use proxy connected ....
this ip[180.97.33.107] will use proxy connected ....
your iptables OUTPUT chain like this....
   Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination

   Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination

   Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination
   1        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            192.168.188.0/24
   2        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1
   3        0     0 RETURN     tcp  --  *      *       0.0.0.0/0            127.0.0.1
   4        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            216.58.194.99        redir ports 12345
   5        0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            180.97.33.107        redir ports 12345

   Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
   num   pkts bytes target     prot opt in     out     source               destination
```

## 清理代理与关闭代理

```bash
Shell> proxy none                 # 清理所有的代理模式
Shell> service redsocks stop             # 关闭代理
```

# 使用 dnsmasq 和 pdnsd 代理 DNS 请求

使用此部分可代理系统的 DNS 请求。以下是使用方法：

## 安装

```bash
Shell> git clone 本仓库
Shell> ./install_dns.sh
Please enter PROXY_DNS_PORT (default: 5300): # 输入 pdnsd 的监听端口
Please enter DEFAULT_NAMESERVER (default: $DEFAULT_NAMESERVER): # 输入默认的 DNS 服务器

┌─────────────────────────────────────────────┤ pdnsd ├─────────────────────────────────────────────┐
│ Please select the pdnsd configuration method that best meets your needs.                          │
│                                                                                                   │
│  - Use resolvconf  : use informations provided by resolvconf.                                     │
│  - Use root servers: make pdnsd behave like a caching, recursive DNS                              │
│                      server.                                                                      │
│  - Manual          : completely manual configuration. The pdnsd daemon                            │
│                      will not start until you edit /etc/pdnsd.conf and                            │
│                      /etc/default/pdnsd.                                                          │
│                                                                                                   │
│                                                                                                   │
│ Note: If you already use a DNS server that listens to 127.0.0.1:53, you have to choose "Manual".  │
│                                                                                                   │
│ General type of pdnsd configuration:                                                              │
│                                                                                                   │
│                                         Use resolvconf                                            │
│                                         Use root servers                                          │
│                                         Manual                                                    │
│                                                                                                   │
│                                                                                                   │
│                                              <Ok>                                                 │
│                                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
# 选择Manual

```

注意可能linux会自动覆盖 `/etc/resolv.conf`，导致 DNS 请求不会被代理，此时需要手动修改 `/etc/resolv.conf`，将 `nameserver` 修改为 `127.0.0.1`.

## 修改代理的 DNS 名单

需要在 `proxy_dns.txt` 中添加域名，每行一个。使用 `.` 作为前缀将匹配所有子域名，例如：

```bash
.google.com
.youtube.com
```

修改后重新执行脚本：

```bash
Shell> ./install_dns.sh
```


## 问题排查

如果您在解析 DNS 时遇到问题，可以按照以下步骤进行问题排查：

### 1. 检查使用 TCP 查找 8.8.8.8 是否成功

```shell
dig +tcp @8.8.8.8 github.com
```

如果不成功，检查 `redsocks` 是否工作正常。

### 2. 检查 `pdnsd` 状态

```shell
dig @127.0.0.1 -p 5300 github.com
```

如果不成功，检查 `pdnsd` 是否正常运行：

```shell
service pdnsd status
```

如果 `pdnsd` 状态不正常，可以使用以下命令启动它：

```shell
service pdnsd start
```

### 3. 检查默认代理状态

```shell
dig @默认代理IP github.com
```

如果不正常，检查默认代理IP是否正确。修改 `dnsserverinfo` 中的 `DEFAULT_NAMESERVER`，然后重新运行 `./install_dns.sh` 来更新配置。

### 4. 检查 `dnsmasq` 状态

```shell
dig @127.0.0.1 github.com
```

如果不正常，使用以下命令检查 `dnsmasq` 是否正常运行：

```shell
service dnsmasq status
```

如果 `dnsmasq` 状态不正常，可以使用以下命令启动它：

```shell
service dnsmasq start
```

### 5. 检查 `/etc/resolv.conf`
查看 `/etc/resolv.conf` 文件，确保 `nameserver` 设置为 `127.0.0.1`，这是代理 DNS 请求所需的设置。如果不是，请手动修改：

```shell
cat /etc/resolv.conf
```

### 6. 检查全流程是否成功

```shell
dig  github.com
```
