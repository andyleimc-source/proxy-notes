# Claude Code 防封与环境风控全链路实战：时区伪装、DNS 泄露根治与指纹防御

> 针对 Anthropic / Claude Code CLI 以及高危 IP/环境检测工具（如 ippure 等）的防御与避坑总结。
> 经过 macOS 生产环境（多台 Mac + Clash Verge + TUN + Tailscale）实测验证。

---

## 核心风控维度与评分逻辑

在针对 Claude Code 或出海开发者的环境检测中，通常包含以下权重：
1. **系统时区（权重 30）**：直接读取 `Intl.DateTimeFormat().resolvedOptions().timeZone` 与中国时区比对。命中 `Asia/Shanghai` 满额 30 分；命中 `Asia/Taipei`（东八区）仍会吃 +18 分（中度连带风险）。
2. **DNS 泄露（核心高危）**：向目标权威服务器发起特定随机子域名解析，若递归解析服务器来自中国电信/联通（如金融街、上海、苏州等），直接判定为国内翻墙。
3. **浏览器语言（权重 24）**：检查 `navigator.languages`，首选或列表中存在 `zh-CN` / `zh` 会给 17~24 分。
4. **字体指纹（权重 20）**：通过 Canvas 测量苹方（PingFang SC）等系统字宽。

---

## 解决方案一：无感时区伪装（0 扣分且不影响 Mac 日常时间）

### 痛点
- 如果直接通过 `sudo systemsetup -settimezone America/Los_Angeles` 修改整机时区，Mac 菜单栏时钟、日历提醒、备忘录时间全部慢 15 小时，严重影响正常作息和办公。

### 解法：终端注入时区环境变量
Claude Code 底层是 Node.js 程序，Node 读取时区时优先遵循当前进程的 `TZ` 环境变量，无需修改整台电脑的时区。

在 `~/.zshrc` 中为 Claude 启动函数注入 `TZ="America/Los_Angeles"`：

```bash
# Claude 启动封装：自动注入美西时区
claude() {
  _cc_trust "$PWD"
  TZ="America/Los_Angeles" command claude --dangerously-skip-permissions "$@"
}

# 快捷别名
cc() { claude --model "opus[1m]" "$@"; }

# worktree 启动封装
cw() {
  _prune_dead_claude_worktrees
  _cc_trust "$PWD"
  TZ="America/Los_Angeles" command claude --dangerously-skip-permissions -w "${1:-$(date +%m%d-%H%M)}" "${@:2}"
}
```

### 验证方法
在 Claude 会话中或终端中测试：
```bash
node -e "console.log(Intl.DateTimeFormat().resolvedOptions().timeZone)"
# 输出：America/Los_Angeles
```
- **效果**：Claude Code 内部读取完全为纯正美西时区（0 风险）；Mac 顶部菜单栏和日历依然保持正常北京时间。

---

## 解决方案二：根治 Clash Verge 机场订阅导致的 DNS 泄露

### 痛点与根因
- 开启 Clash Verge 的 **TUN 模式** 并挂上美国代理节点后，检测页面仍出现大量中国 DNS 泄露（例如上海、苏州、金融街 IP）。
- **根因**：国内绝大多数机场订阅文件中，硬编码了国内公共 DNS：
  `119.29.29.29`（腾讯）、`223.5.5.5`（阿里）、`https://dns.pub/dns-query` 等。
- 当 TUN 模式劫持全系统 `any:53` DNS 请求时，所有域名的解析全部由 Clash 内核代为向上游国内 DNS 发起查询，腾讯/阿里 recursive 节点自然暴露了中国区域。
- 单纯在 Mac 网络设置里修改 Wi-Fi DNS 是**无效的**，因为 TUN 虚拟网卡已经全权接管了流量。

### 根治方案：使用扩展脚本覆写内核 DNS
在 Clash Verge 中使用 Script 扩展（订阅更新时自动重新执行，永不被冲刷覆盖）。

编辑 Clash Verge 的全局或订阅扩展脚本（`Script.js`）：

```javascript
// Clash Verge 扩展脚本：阻断境外 DNS 泄露，保留国内极速解析
function main(config, profileName) {
  if (!config.dns) config.dns = {};
  
  // 强制遵循规则分流
  config.dns['respect-rules'] = true;
  
  // 默认 nameserver 全部采用纯正境外公共 DNS
  config.dns.nameserver = [
    'https://1.1.1.1/dns-query',
    'https://dns.google/dns-query',
    '1.1.1.1',
    '8.8.8.8'
  ];
  
  // 节点域名解析专用的 nameserver
  config.dns['proxy-server-nameserver'] = [
    '1.1.1.1',
    '8.8.8.8'
  ];
  
  // 国内域名（geosite:cn）与局域网域名定向路由到阿里/腾讯 DNS
  config.dns['nameserver-policy'] = {
    'geosite:cn,private': [
      '223.5.5.5',
      '119.29.29.29'
    ]
  };
  
  return config;
}
```

- **生效原理**：所有境外流量、海外 API（Anthropic、OpenAI、Stripe）以及泄露测试，全部通过 Cloudflare / Google DNS 解析；国内域名保留国内阿里/腾讯解析，两全其美，彻底杜绝 DNS 泄露。

---

## 解决方案三：浏览器语言与字体指纹说明

1. **浏览器语言（权重 24）**：
   - 检测脚本扫描的是整组 `navigator.languages`（例如 `["en-US", "zh-CN", "zh"]`）。
   - 即使把英文置顶，只要列表中残留中文项，依然会判定中度风险（+17 分）。
   - 若要清零：在 Chrome「设置 → 语言（`chrome://settings/languages`）」中，点击中文右侧的三点，选择 **Remove（删除）**，只保留 `English (United States)`。
2. **中文字体指纹（权重 20）**：
   - 测试页通过 Canvas 绘制特定字符并测量像素宽度，探测是否存在 `PingFang SC`（苹方）等字体。
   - **无需恐慌，不用折腾**：苹方是 macOS 系统的只读核心字体，海外多语言用户、海外华人 Mac 均自带此字体，平台风控（Anthropic / Cloudflare）绝不会单凭中文字体封号。

---

## 避坑辟谣：常见误区

### 误区一：必须买独立美国 VPS 自建节点？
- **事实**：如果当前机场节点的出口 IP 未被大量滥用进黑名单，完全不需要多花钱买 VPS。自建 VPS 维护成本高，且单 IP 一旦被封全盘皆输。

### 误区二：必须把终端的 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量全删了？
- **严重事故预警**：很多教程建议"纯靠 TUN，终端不设任何代理环境变量"。但在多网卡环境下（尤其是开了 **Tailscale** 的机器），Tailscale MagicDNS 会抢答 DNS，导致进 TUN 的请求变成了裸 IP，无法匹配 `DOMAIN-*` 白名单规则，直接掉进 DIRECT 直连，引发 Claude Code 登录报 403。
- **正解**：终端必须保留代理环境变量（指向本地端口如 `http://127.0.0.1:7897`），让请求带着完整域名进入代理客户端，配合 TUN 双保险。
