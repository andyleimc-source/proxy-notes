# Clash Verge 流量白名单改造（含 Claude Code 登录 403 大坑）

> 一份给 **AI 编码助手（Claude Code / Cursor 等）照着执行**的 runbook。
> 每一步都带命令和预期输出，按顺序做、每步验证通过再走下一步，可以零出错完成。
> 人类读者直接看「背景」和「大坑」两节即可理解全部来龙去脉。

## 背景：为什么要改

**现象**：200GB/月 的订阅一个多月烧掉 105GB，且严重倒挂——上行 72GB > 下行 33GB。

**排查**（方法可复用）：

1. 看实时连接找流量大户：
   ```bash
   curl -s --unix-socket /tmp/verge/verge-mihomo.sock -H "Authorization: Bearer <secret>" http://localhost/connections
   ```
2. 对高上行目标 IP 做 whois → `160.79.104.10` 归属 **Anthropic, PBC**，即 Claude Code API。AI 编码工具要频繁上传代码上下文，上行大是刚需，这部分省不掉、也必须走代理。
3. 真正的浪费在**兜底规则**：订阅默认 `MATCH,Proxy`（黑名单模式）——Apple 系统更新/App Store（`blobstore.apple.com` 等被订阅显式指向 Proxy）、`DOMAIN-KEYWORD,amazon`（等于全球 AWS S3/CDN 全走代理）、Dropbox / Adobe / Microsoft 后台流量……全在偷偷烧订阅流量。

**修法**：用 Clash Verge Rev 的**全局 Merge 覆写**，把订阅的 `rules:` **整体替换**成白名单——名单内（AI 工具、Google、GitHub、社媒等真正需要代理的服务）走 `Proxy`，兜底改 `MATCH,DIRECT` 默认直连。订阅自动更新不会冲掉 Merge 覆写。

**效果**：只有白名单域名消耗订阅流量，系统后台杂音全部直连归零。

---

## ⚠ 大坑：改完后浏览器正常，终端里 Claude Code 登录 403

这是本次改造踩到的最重要的坑，**先读懂再施工**。

**症状**：改造后浏览器一切正常，但终端里 `claude` 登录失败——浏览器 OAuth 页面显示成功，终端报错（实际是 API 请求 403）。`git push`、`npm` 等命令行工具同理可能受影响。

**原因链**（四环，缺一不复现）：

1. 终端 CLI 工具（Node/Go 程序）**不读 macOS 系统代理**，全靠 TUN 模式接管流量。
2. TUN 靠 **fake-ip** 起作用：mihomo 劫持 DNS，把域名解析成 `198.18.x.x` 假 IP，流量进 TUN 时凭假 IP 反查出域名，域名规则才能匹配。
3. 如果机器上有**别的东西抢答 DNS**（本案是 Tailscale MagicDNS，系统首选 DNS 变成 `100.100.100.100`，DNS 查询走 Tailscale 自己的接口、mihomo 的 `dns-hijack` 劫持不到），域名就解析成**真实 IP**——流量进 TUN 时只剩裸 IP、没有域名。
4. 裸 IP 匹配不了任何 `DOMAIN-*` 白名单规则 → 掉进兜底。**改造前**兜底是 `MATCH,Proxy`，裸 IP 也走代理，问题被掩盖；**改造后**兜底是 `MATCH,DIRECT`，裸 IP 从国内直连出去 → Anthropic 拒绝不支持地区 → 403。

浏览器为什么没事：浏览器走**系统代理**（127.0.0.1:7897），CONNECT 请求自带域名进 mihomo，白名单正常匹配。

**配套修复**（施工步骤里包含）：给终端也挂上代理环境变量。请求带着域名进 mihomo，白名单照常生效——名单内走代理、名单外由 mihomo 直连，行为和浏览器完全一致。这一步**无论你的 DNS 当前是否被抢答都建议做**：它没有副作用，且未来某天开了 Tailscale MagicDNS / 换了 DNS 配置也不会突然踩坑。

---

## 施工 Runbook（AI 按此执行）

> 环境假设：macOS + Clash Verge Rev（mihomo 内核），系统代理与 TUN 已开。
> 以下 `$VDIR` 指 Clash Verge 配置目录。

### Step 0 — 前置侦察（只读，不改任何东西）

```bash
VDIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
ls "$VDIR" || echo "目录不存在，Clash Verge 版本不同，先定位配置目录"
```

**0a. 确定内核控制接口**（新版走 unix socket，老版走 TCP）：

```bash
grep -E "external-controller|secret" "$VDIR/clash-verge.yaml"
```

- 有 `external-controller-unix: /tmp/verge/verge-mihomo.sock` → 后续统一用
  `curl --unix-socket /tmp/verge/verge-mihomo.sock -H "Authorization: Bearer <上面看到的 secret>" http://localhost/...`
- 只有 `external-controller: 127.0.0.1:9097` 之类 → 用 `curl -H "Authorization: Bearer <secret>" http://127.0.0.1:9097/...`

**0b. 确定代理组名**（⚠ 别人的订阅未必叫 `Proxy`，可能是 `🚀 节点选择` 等）：

```bash
curl -s --unix-socket /tmp/verge/verge-mihomo.sock -H "Authorization: Bearer <secret>" http://localhost/proxies | python3 -c "
import json,sys
for n,p in json.load(sys.stdin)['proxies'].items():
    if p['type']=='Selector' and n!='GLOBAL': print(n,'->',p.get('now'))"
```

记下主选择组的名字。**如果不叫 `Proxy`，后面 merge-whitelist.yaml 里所有 `,Proxy` 要全局替换成实际组名**（`sed -i '' 's/,Proxy$/,你的组名/'`）。

**0c. 确定混入端口**（Verge Rev 默认 7897，老 Clash 常见 7890）：

```bash
grep mixed-port "$VDIR/clash-verge.yaml"
```

**0d. 记录改造前状态**（回滚参照）：

```bash
curl -s --unix-socket /tmp/verge/verge-mihomo.sock -H "Authorization: Bearer <secret>" http://localhost/rules | python3 -c "
import json,sys; r=json.load(sys.stdin)['rules']; print('规则数:',len(r),'| 兜底:',r[-1]['type'],'->',r[-1]['proxy'])"
```

预期看到几百条规则、兜底 `Match -> Proxy`（黑名单模式，即本次要改掉的状态）。

### Step 1 — 备份并写入白名单 Merge

```bash
cp "$VDIR/profiles/Merge.yaml" "$VDIR/profiles/Merge.yaml.bak-$(date +%F)"
```

把本目录的 [`merge-whitelist.yaml`](merge-whitelist.yaml) 内容写入 `$VDIR/profiles/Merge.yaml`，文件结构为：

```yaml
profile:
  store-selected: true

rules:
  # ……merge-whitelist.yaml 的完整 rules 列表……
```

⚠ 注意：
- `Merge.yaml` 是**全局 Merge**，对所有订阅生效。若只想对某个订阅生效，改该订阅挂的专属 merge 文件（Verge UI「右键订阅 → 编辑 Merge」对应的那个文件）。
- 如果原 Merge.yaml 里有你自己的其他覆写内容，保留它们，只增加/替换顶层 `rules:` 键。
- 组名不是 `Proxy` 的记得替换（Step 0b）。

写完自检：

```bash
python3 -c "import yaml; d=yaml.safe_load(open('$VDIR/profiles/Merge.yaml')); assert d['rules'][-1]=='MATCH,DIRECT'; print('yaml ok, rules:',len(d['rules']))"
```

### Step 2 — 终端代理环境变量（配套修复，防 403 大坑）

追加到 shell 配置（zsh 为例；端口用 Step 0c 查到的值）：

```bash
cat >> ~/.zshrc << "EOF"

# 终端代理：配合 Clash 白名单(兜底 DIRECT)。终端请求带域名进 mihomo，白名单才能生效
export https_proxy=http://127.0.0.1:7897
export http_proxy=http://127.0.0.1:7897
export all_proxy=socks5://127.0.0.1:7897
export HTTPS_PROXY=$https_proxy HTTP_PROXY=$http_proxy ALL_PROXY=$all_proxy
export no_proxy="localhost,127.0.0.1,*.local,100.64.0.0/10,192.168.0.0/16,10.0.0.0/8"
export NO_PROXY=$no_proxy
EOF
```

`no_proxy` 里的 `localhost,127.0.0.1` **必须有**——Claude Code OAuth 登录回调走 localhost，被代理会挂。

### Step 3 — 应用配置

磁盘上改 Merge 文件后**内核不会自动重载**，二选一：

- GUI：Clash Verge 界面里把当前订阅**重新点选一次**（触发重新合并 + 内核重载）；
- 命令行（无人值守可用）：整个重启 App，启动时会重新合并：

  ```bash
  osascript -e 'quit app "Clash Verge"'; sleep 3; open -a "Clash Verge"
  ```

  重启期间网络闪断几秒属正常。

### Step 4 — 验证（全部通过才算完成）

```bash
# 4a. 规则已替换：预期 rules 总数 ≈ 68，兜底 Match -> DIRECT
curl -s --unix-socket /tmp/verge/verge-mihomo.sock -H "Authorization: Bearer <secret>" http://localhost/rules | python3 -c "
import json,sys; r=json.load(sys.stdin)['rules']; print(len(r), r[-1]['type'], '->', r[-1]['proxy'])"

# 4b. fake-ip 是否健康：预期解析出 198.18.x.x
#     若返回真实 IP → 你就是「大坑」一节说的情况(DNS 被抢答)，Step 2 的终端代理救了你
dscacheutil -q host -a name api.anthropic.com

# 4c. 白名单域名可达：预期 404（到达了 Anthropic 服务器）；403 = 还在直连出国，有问题
curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 https://api.anthropic.com/

# 4d. 国内直连正常：预期 200
curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 https://www.baidu.com/

# 4e. 分流链路抽查：白名单域名 rule 应为 DomainSuffix -> Proxy，其余 Match -> DIRECT
curl -s --unix-socket /tmp/verge/verge-mihomo.sock -H "Authorization: Bearer <secret>" http://localhost/connections | python3 -c "
import json,sys
for c in json.load(sys.stdin).get('connections') or []:
    m=c['metadata']; print(m.get('host') or m.get('destinationIP'), '|', c.get('rule'), '->', (c.get('chains') or ['?'])[-1])" | sort -u | head -20

# 4f. 终端新开一个窗口（让 Step 2 生效），跑 Claude Code 端到端
claude -p "reply with exactly: ok"
```

**判读速查**：

| 观察 | 结论 |
|---|---|
| 4c 返回 404 | ✅ 走代理到达 Anthropic（404 是 API 根路径的正常响应）|
| 4c 返回 403 | ❌ 流量从国内直连出去了，回到「大坑」一节排查 |
| 4e 里目标只有裸 IP 没域名 | DNS 被抢答（Tailscale MagicDNS 等），终端必须依赖 Step 2 的环境变量 |
| 浏览器好使、终端 403 | 就是「大坑」本坑，检查 Step 2 是否做了、是否开了新终端窗口 |

### 回滚

```bash
cp "$VDIR/profiles/Merge.yaml.bak-<日期>" "$VDIR/profiles/Merge.yaml"
# 再执行 Step 3 重新应用
```

---

## 日常注意事项

- **白名单外的国外网站默认直连**（在墙内 = 打不开）。要临时加站：往 `Merge.yaml` 的 `rules:` 里 `MATCH,DIRECT` **之前**加一条 `DOMAIN-SUFFIX,某域名,Proxy`，再执行 Step 3。
- Claude Code 上行流量大是刚需（频繁上传代码上下文），这部分省不掉，白名单省的是它以外的所有杂音。
- 白名单清单（Anthropic / OpenAI / Google 全家 / GitHub / Meta 全家 / X / LinkedIn）见 [merge-whitelist.yaml](merge-whitelist.yaml)，按需增删。
