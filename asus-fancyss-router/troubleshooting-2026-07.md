# RT-AC86U + fancyss 节点全 timeout 排障复盘（2026-07-01）

> 环境：华硕 RT-AC86U，koolshare 官改梅林固件 `3.0.0.4.386_46092_koolshare`，科学上网插件 **fancyss**，机场 shadowsocks.au（订阅域名走 CloudFront，节点域名 `*.tr202606.com`）。路由器装了 Tailscale（tailnet IP `100.116.16.72`）。

## 现象

- 之前一直正常，**某两天突然全部节点连不上**，"什么都没改"。
- 插件页：**国外链接 ✗ / 国内连接 ✓**，节点列表"当前没有可显示的节点"。
- 重新填订阅链接 → 同步日志 `直连下载订阅失败` → 想用节点代理下载又"当前节点工作异常" → 0 节点。
- 同一条订阅链接在电脑本地 Clash 里能用。

## 根因：三个问题叠在一起

### 1. 机场换了新协议，旧插件解析不了
订阅里新增了 `hysteria2 / AnyTLS / tuic` 节点。路由器上的 **fancyss 3.5.28 解析不了这些新协议 → 0 节点**。
→ 升级到 **3.5.30**（新协议二进制 `xray / hysteria2 / anytls-zig / tuic-client` 才齐全）。

### 2. 订阅域名 DNS 解析失败（鸡生蛋 · 第一层）
机场订阅域名 `s2.trojanflare.one` 走 CloudFront，被 fancyss 的 **smartdns 判为墙外域名**，DNS 查询丢给 gfw 组（8.8.8.8 / 1.1.1.1）——而这些要**经过代理**才能到，代理此刻正好挂了 → **域名解析失败 → 下不了订阅**。
- 关键判断：**IP 能 ping 通（网络是通的），只是域名解析不出来**。这才是"突然不行"的直接原因。
- 为什么以前行：以前有可用节点，代理起着，smartdns 能正常解析墙外域名。一旦所有节点失效，就进入"解析要靠代理、代理要靠节点、节点要靠订阅、订阅要靠解析"的死循环。

### 3. 节点域名 DNS 同样解析失败（鸡生蛋 · 第二层）
就算订阅拉到了，节点域名 `*.tr202606.com` 也是墙外域名，走同一条死 DNS 路径 → 代理起不来、延迟测试全 timeout。

### 附带坑：订阅链接对 UA 敏感
机场对**默认 curl UA** 返回 `访问受限` 占位（124 字节，单个假节点 `trojan://blocked@127.0.0.1:1`）。必须带 fancyss 的 UA 才返回真实节点：
```
AsusWRT|koolshare|RT-AC86U|386_46092_koolshare|fancyss|hnd|full|3.5.30|curl|v2rayN
```

## 解决办法（按顺序）

### A. 升级 fancyss（路由器自己下不了 GitHub → 从能翻墙的电脑代下、局域网推过去）
路由器点"升级"没用，因为它下载 GitHub 也走那条死路径（直连被墙 / 代理没起）。做法：

1. 在能访问 GitHub 的电脑上下载对应平台包并校验 MD5（平台 = 插件名里的 `hnd_full`）：
   ```
   # 版本清单（含各平台 MD5）
   https://raw.githubusercontent.com/hq450/fancyss/3.0/packages/version.json.js
   # 升级包本体
   https://raw.githubusercontent.com/hq450/fancyss/3.0/packages/fancyss_hnd_full.tar.gz
   ```
   本机 `md5 -q fancyss_hnd_full.tar.gz` 要等于清单里的 `md5_hnd_full`。
2. 路由器后台开 SSH（系统管理 → 系统 → Enable SSH，LAN only，端口 22）。
3. 局域网 SCP 推过去（**dropbear 没有 sftp-server，scp 要加 `-O` 走旧协议**）：
   ```
   scp -O fancyss_hnd_full.tar.gz leimingcan@192.168.50.1:/tmp/shadowsocks.tar.gz
   ```
4. SSH 进去，跑官方安装脚本（**这就是"升级"按钮内部做的事，只是网络换成局域网**，不碰固件，零变砖风险）：
   ```
   cd /tmp && tar -zxf shadowsocks.tar.gz && chmod a+x shadowsocks/install.sh && sh shadowsocks/install.sh
   rm -rf /tmp/shadowsocks*
   ```
   注：走 SSH 手动装**不要**设 `/tmp/fancyss_self_update_installing` 标志——那是网页自更新时"延迟重启 websocketd 免得杀掉自己"用的，SSH 装反而希望它完整重启。

### B. 破 DNS 鸡生蛋：让机场域名走国内 DNS 直接解析（永久修复）
fancyss 的 DNS 结构：dnsmasq(:53) → 转发给 smartdns(`127.0.0.1#7913`)。给 dnsmasq 加**域名专属上游**，让订阅域名 + 节点域名绕开 smartdns/代理，直接问国内 DNS（国内 DNS 能把 CloudFront/节点解析成可达 IP）。

写到 dnsmasq 的持久化 include 目录（`/etc/dnsmasq.conf` 里已有 `conf-dir=/jffs/configs/dnsmasq.d`，jffs 持久化、重启不丢）：
```
# /jffs/configs/dnsmasq.d/fancyss-sub-dns.conf
server=/trojanflare.one/223.5.5.5
server=/trojanflare.one/114.114.114.114
server=/tr202606.com/223.5.5.5
server=/tr202606.com/114.114.114.114
```
> ⚠️ 换机场后订阅域名/节点域名会变，要相应改这里的域名。

让它立即生效（**不要用 `service restart_dnsmasq`**——那会重生成 `/etc/dnsmasq.conf`、冲掉 fancyss 写进去的 `server=127.0.0.1#7913`）。直接原样重启 dnsmasq 进程即可（不动配置文件）：
```
killall dnsmasq; sleep 1; dnsmasq --log-async
```
验证：`nslookup s2.trojanflare.one 127.0.0.1` 和 `nslookup hk-1.tr202606.com 127.0.0.1` 都能解析出 IP 即成功。

（应急一次性方案：往 `/etc/hosts` 加 `<CloudFront IP> s2.trojanflare.one`，fancyss 的 curl 认 hosts，能拉一次订阅救急；但重启会丢、IP 会变，不如上面的永久规则。）

### C. 同步订阅 + 选节点
- 触发订阅同步（这条也是"定时更新"用的）：
  ```
  /koolshare/scripts/ss_node_subscribe.sh fancyss 3
  ```
- 网页"节点管理"里选节点后**必须点最底下「保存&应用」**——光选中不点应用，代理不会真正启动（`fss_node_current` 空 = 没节点在跑）。

## 一句话心智

> **节点全 timeout、路由器又下不了订阅** → 十有八九是 **DNS 鸡生蛋**（墙外域名要靠代理解析、代理要靠节点、节点要靠订阅、订阅要靠解析），不是节点真死。破法：让订阅域名 + 节点域名走国内 DNS 直连解析。协议对不上（0 节点）则是插件版本旧，需升级。

## 可复用命令备忘（SSH 进路由器）

```
# 当前 fancyss 版本
cat /koolshare/ss/version
# 节点列表（新版 schema2 存储）
/koolshare/bin/node-tool list
/koolshare/bin/node-tool list --format json
# 当前选中节点（schema2 的键是 fss_node_current，不是旧的 ssconf_basic_node）
dbus get fss_node_current
# xray 实际连的服务器（真相以此为准，current-env 有缓存不可靠）
grep -oE '"address": *"[^"]+"' /koolshare/ss/xray.json
```
