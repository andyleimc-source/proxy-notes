# RT-AC86U 从零配置 FancySS Lite + VLESS-Reality（Clash 订阅转换与全屋透明代理）

适用场景：路由器重置或带到新网络环境后，在 **Koolshare / Koolcenter 改版梅林** 上离线安装 FancySS Lite、导入 Clash YAML 里的 VLESS-Reality 节点、开启 DNS 劫持，并解决 Mac 客户端退出 Clash 后终端仍不通的问题。

## 1. 接线与初始化

1. 上级光猫/网口接路由器的 **蓝色 WAN 口**。
2. 电脑/手机连上默认 Wi-Fi，打开 `192.168.50.1`（或 `router.asus.com`），按向导设好 Wi-Fi 与管理员密码；上网方式先选 **自动获取 IP（DHCP）**（光猫本身拨号时直接联网；光猫桥接才改 PPPoE）。
3. 确认左侧有「软件中心」（需 Koolshare / Koolcenter 改版梅林；原厂固件不支持）。
4. 在「系统管理 → 系统设置」开启 SSH：`LAN only`、端口 `22`、允许密码登录 `是`，点底部 **应用本页面设置**。

## 2. 安装 FancySS Lite

> 为什么选 Lite：RT-AC86U 仅 512MB 内存、47MB JFFS，Merlin Clash 容易吃满内存；`fancyss_hnd_lite` 解压约 19MB，用 `xray-core + chinadns-ng + ipset`，原生支持 **VLESS-Reality** 且最省资源。

最新版本可在 `hq450/fancyss_history_package` 的 `fancyss_hnd/md5sum.txt` 查看：

```bash
# 1. 下载离线包
curl -L -o ~/tmp/fancyss_hnd_lite_3.5.29.tar.gz \
  "https://raw.githubusercontent.com/hq450/fancyss_history_package/master/fancyss_hnd/fancyss_hnd_lite_3.5.29.tar.gz"

# 2. 传到路由器 /tmp/upload/（RAM 分区，不占 JFFS）
scp -O ~/tmp/fancyss_hnd_lite_3.5.29.tar.gz <user>@192.168.50.1:/tmp/upload/

# 3. SSH 执行软件中心离线安装
ssh <user>@192.168.50.1 \
  "dbus set soft_name=fancyss_hnd_lite_3.5.29.tar.gz && sh /koolshare/scripts/ks_tar_install.sh"
```

## 3. 导入 Clash YAML 里的 VLESS-Reality 节点

FancySS 的在线订阅脚本（`ss_node_subscribe.sh`）不直接解析 Clash YAML 格式，但支持通过 `ss_base64_links`（`action=4`）批量导入标准 `vless://` 链接：

```bash
# 1. 本地把 Clash 订阅里的 vless 节点转成 vless:// 链接并 base64 编码
SUB_URL="<your-clash-subscription-url>"
python3 - << 'EOF' > /tmp/nodes.b64
import os, urllib.request, base64, urllib.parse
raw = urllib.request.urlopen(os.environ["SUB_URL"]).read().decode()
in_p, nodes, cur = False, [], {}
for line in raw.splitlines():
    s = line.strip()
    if s.startswith("proxies:"): in_p = True; continue
    if in_p and line and not line.startswith((" ", "-")): break
    if not in_p or not s: continue
    if s.startswith("- "):
        if cur: nodes.append(cur)
        cur = {}; s = s[2:].strip()
    if ":" in s and not s.startswith("#"):
        k, v = s.split(":", 1)
        v = v.strip().strip('"').strip("'")
        if v: cur[k.strip()] = v
if cur: nodes.append(cur)
links = []
for n in nodes:
    if n.get("type") != "vless": continue
    q = {"encryption":"none","security":"reality","sni":n.get("servername",""),
         "fp":n.get("client-fingerprint","chrome"),"pbk":n.get("public-key",""),
         "sid":n.get("short-id",""),"type":n.get("network","tcp")}
    if n.get("flow"): q["flow"] = n["flow"]
    links.append(f"vless://{n['uuid']}@{n['server']}:{n['port']}?{urllib.parse.urlencode(q)}#{urllib.parse.quote(n['name'])}")
print(base64.b64encode(("\n".join(links) + "\n").encode()).decode(), end="")
EOF

# 2. 传到路由器并调用 FancySS 离线导入
scp -O /tmp/nodes.b64 <user>@192.168.50.1:/tmp/nodes.b64
rm -f /tmp/nodes.b64
ssh <user>@192.168.50.1 \
  'dbus set ss_base64_links="$(cat /tmp/nodes.b64)" && rm -f /tmp/nodes.b64 && sh /koolshare/scripts/ss_node_subscribe.sh fancyss 4'
```

## 4. 开启代理与推荐参数

```bash
ssh <user>@192.168.50.1 '
  /koolshare/bin/node-tool list
  dbus set ss_basic_enable=1
  dbus set ssconf_basic_node=1      # 选中节点 ID
  dbus set ss_basic_mode=2          # 2=大陆白名单模式（国内直连、国外代理）
  dbus set ss_basic_dns_hijack=1    # 开启 DNS 劫持，防设备写死公共 DNS 绕过分流
  sh /koolshare/scripts/ss_config.sh fancyss start_by_ws
'
```

验证路由器本身连通性：
```bash
ssh <user>@192.168.50.1 "sh /koolshare/scripts/ss_status.sh"
```

## 5. Mac 客户端退出 Clash 后仍不能翻墙的排查清单

1. **Wi-Fi DNS 被本机代理软件写死**：Clash Verge（TUN / DNS 覆写）退出后，系统 Wi-Fi DNS 可能仍残留在 `114.114.114.114` 等国内 DNS，导致海外域名解析被污染。
   - 检查：`networksetup -getdnsservers "Wi-Fi"`
   - 恢复 DHCP 自动获取：`networksetup -setdnsservers "Wi-Fi" Empty`
2. **终端环境变量写死了本地代理端口（如 `127.0.0.1:7897`）**：网页正常但终端报错 `Connection refused`。
   - 在 `~/.zshrc.local` 里改成仅当端口有监听时才导出：
     ```zsh
     if nc -z 127.0.0.1 7897 >/dev/null 2>&1; then
       export http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897
       export HTTP_PROXY=$http_proxy HTTPS_PROXY=$https_proxy ALL_PROXY=$all_proxy
     fi
     ```
   - 已打开的老终端窗口需新开或执行 `unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY`。
3. **CLI 包装脚本误判裸连**：若 `agy` 等包装脚本只检测 `127.0.0.1:7897` 是否存在，在路由器透明代理下会误报「裸连」；可在检测 7897 失败后追加 `curl -sf --noproxy '*' --max-time 2 https://www.google.com/generate_204 >/dev/null 2>&1`，通则静默放行。
