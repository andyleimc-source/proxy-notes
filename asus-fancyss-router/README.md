# ASUS RT-AC86U + fancyss

华硕 RT-AC86U（koolshare 官改梅林固件）上科学上网插件 **fancyss** 的排障笔记与远程运维工具。

## 内容

| 文件 | 说明 |
|------|------|
| [troubleshooting-2026-07.md](troubleshooting-2026-07.md) | 节点全 timeout 排障复盘：DNS 鸡生蛋 + 协议升级 + 手动升级 fancyss + UA 敏感订阅 |
| `node-ctl` | 用 Claude Code / 命令行**远程切换节点 + 测速**的工具（下面） |
| `lib/router-node-ctl.sh` | 上面工具在路由器侧执行的逻辑（随 SSH 送入，不落地安装） |

---

## node-ctl —— 远程节点控制

在**任意一台 Mac**（只要在 Tailscale 上、能上网）远程列节点、测速、切节点。默认走路由器的
**Tailscale IP**，所以人在外面也能用（路由器把发往其 Tailscale IP 的流量 DNAT 到 LAN，SSH 能到）。

### 首次配置（每台新 Mac 一次）

```bash
brew install hudochenkov/sshpass/sshpass          # 依赖
cd asus-fancyss-router
cp .router-env.example .router-env                # 填 ROUTER_HOST/USER/PASS（.router-env 不进 git）
```

前提：① 本机 `tailscale` 在线；② 路由器后台 SSH 开着（系统管理 → 系统 → Enable SSH，LAN only，端口 22）。

### 用法

```bash
./node-ctl list            # 列出所有节点（* 标记当前）
./node-ctl current         # 当前生效节点（含 xray 实连服务器 + 运行状态）
./node-ctl speed           # 原生延迟测试，按延迟升序（覆盖所有协议，约 30-60s）
./node-ctl switch <id>     # 切到指定 id 节点并应用，验证实连 + 出口
```

### 让 Claude Code 帮你切

直接说，例如：
- 「**列一下节点速度**」 → 跑 `./node-ctl speed`
- 「**切到最快的日本节点**」 → 看 speed 结果挑一个 → `./node-ctl switch <id>`
- 「**现在用的哪个节点**」 → `./node-ctl current`

### 示例输出

```
$ ./node-ctl speed
延迟    当前 ID  协议        节点名
91ms         7   trojan      日本-TY-1-:1
99ms         14  trojan      日本-OS-1-:0.6
106ms        13  hysteria2   日本-TY-5-HY2-:1
...
374ms    *   3   trojan      中国香港-HK-1-:0.7      ← 当前节点偏慢
timeout      24  trojan      新加坡-SG-1-:1          ← 当前不可用
```

## 原理速记（改机场/换固件时看这里）

- **测速**：触发 fancyss 原生 `ss_webtest.sh 2`，读 `/tmp/upload/webtest.stream` 每节点最终延迟。是**真实端到端落地延迟**，覆盖 trojan/hysteria2/anytls 等所有协议（自己测 TCP 握手会把 hysteria2/tuic 这类 UDP 节点误判为死）。
- **切节点**：schema2 存储，当前节点键是 `fss_node_current`（+ `fss_node_current_identity`），**不是**旧的 `ssconf_basic_node`；设好后 `ss_config.sh start` 应用。`identity` 是节点身份哈希，重新订阅导致 id 重排后仍能对上。
- **当前节点真相**以 `xray.json` 的 `address` 为准，`node-tool current-env` 有缓存不可靠。
- **远程可达**依赖：路由器 Tailscale 在线 + SSH 开着。SSH 若被关掉，工具会连不上——去后台重新开 SSH 即可。
- **另一台 Mac 也要用**：把 `.router-env` 复制过去（或各自重建），装好 sshpass。
