# 任务卡｜在自己的 Linux 服务器上使用 Claude Code 和固定出口

完成后，你可以从自己的电脑 SSH 到服务器，在 tmux 中运行官方 Claude Code。若购买独享固定 IP，下面的启动命令会让 Claude Code 使用该出口。所有账号、机器和订单都由你自己持有。先确认你的使用地点和账号符合服务条件，代理出口不会改变实际使用地点。[Anthropic 支持地区](https://www.anthropic.com/legal/supported-regions)

## 1. 确认预算，再下单

| 项目 | 上次实际购买 | 你下单时要核对 |
| --- | --- | --- |
| Linux 服务器 | TMHHost 洛杉矶 US 4837 1，Ubuntu 22.04 x86_64，1 核、1 GB 内存、10 GB 磁盘，¥38/月 | 此规格完成了安装和授权状态检查。Claude Code 官方列出的内存要求为 4 GB 起，新购按 4 GB 起询价。确认有公网 SSH、网页控制台和恢复入口。 |
| 指定出口（按需） | IPRoyal ISP Proxies，新加坡、1 个独享 IPv4、30 天。标准报价 $5.20，选 IPQS 高级筛选后实付 $7.02。该订单公平使用额度 100 GB/月。 | 需要固定出口才购此项。核对总价、额度、续期保留原 IP 和自动续费。ISP 产品可以由机房托管，商家的评分筛选也不能证明线路接入了真实家庭。 |
| Claude 订阅 | 单独向 Claude 购买 | 登录自己的账号，在订阅页面确认套餐包含 Claude Code、结算周期和实付金额。已有合适订阅可直接使用。 |

服务器及代理的参考价来自 2026 年 11 月的一次实际订单，当时两项都关闭了自动续费。今天的库存、价格和条款以你自己的结算页为准。[TMHHost](https://www.tmhhost.com/) · [IPRoyal ISP 产品](https://iproyal.com/isp-proxies/) · [Claude 套餐](https://claude.com/pricing) · [Claude Code 系统要求](https://code.claude.com/docs/en/setup#system-requirements)

- [ ] 在服务器商家选 Linux VPS、机房、内存、Ubuntu LTS 和月付。付款后在自己的密码管理器记下控制台入口、SSH 用户、公网地址、端口和续费日。
- [ ] 需要固定出口时，在 IPRoyal 后台选 **ISP → Create a new order**，选国家、数量 1、期限 30 天。复现上述订单时选择 Singapore 和高级 IPQS 筛选，未加购多设备，未勾选每次续费更换 IP。付款后打开此订单，找到协议、端点、端口、认证方式及分配的出口 IPv4。到期前若要保留地址，按订单条款提前续费。[供应商操作说明](https://help.iproyal.com/en/articles/7955587-how-to-use-isp-proxies)

## 2. 从自己的电脑安全连入新服务器

服务器面板给出 SSH 用户和端口。下面的 SERVER、USER、PORT 分别替换为自己的公网地址、Linux 用户和 SSH 端口。以下第一组命令在**个人电脑**执行。

```bash
ssh-keygen -t ed25519 -f ~/.ssh/claude-vps
cat ~/.ssh/claude-vps.pub
ssh -p PORT -i ~/.ssh/claude-vps USER@SERVER
```

生成时设置口令；如果同名密钥已存在就复用，或换新文件名。把 `.pub` 那一整行添加到面板的 SSH 公钥，或通过网页控制台加到目标用户的 `~/.ssh/authorized_keys`（目录 700、文件 600）。首次连接时用控制台显示的主机密钥指纹核对 SSH 提示。若镜像只给 root 初始密码，先用控制台建普通用户并加入 sudo 组，再为该用户安装公钥。

在**服务器**上运行以下命令。保留原连接，用第二个窗口验证公钥登录，运行 `sudo -v`。若要关密码登录，先在控制台保留恢复入口，再调整 sshd 的 `PubkeyAuthentication yes`、`PasswordAuthentication no` 和 `KbdInteractiveAuthentication no`，用 `sudo sshd -t` 通过后才 `sudo systemctl reload ssh`，从第三个新窗口复验。

```bash
sudo apt update && sudo apt upgrade
sudo apt install ca-certificates curl git python3 tmux
free -h
df -h /
swapon --show
```

低配实机只用内存压缩交换区 zram，以 `swapon --show` 只列出 `/dev/zram0` 为准。1 GB 机器同时跑大型构建或多个客户端时容易耗尽内存；要复用旧机，先看可用内存、磁盘和内核是否支持 zram。可选的 Tailscale 用自己的账号分别加入个人电脑与 VPS，服务器运行 `sudo tailscale up`，再以 `tailscale ip -4` 给出的地址验证 SSH。这个地址用于管理服务器。[Tailscale Linux 安装](https://tailscale.com/docs/install/linux)

## 3. 把固定出口配给这台服务器上的 Claude Code

先分清三个值。**VPS 公网地址**用于 SSH，也是按来源 IP 认证时要加入商家白名单的地址。**代理端点和端口**是客户端连接的入口。**分配的出口 IP**是目标网站应看到的地址。固定代理通过客户端设置生效，VPS 网卡保留原地址。一台美国 VPS 使用新加坡出口时，往返延迟可能增加。

优先使用订单给出的用户名和密码，仅录入自己的服务器。选白名单认证时，先在订单允许的来源中填 VPS **实际直连的公网 IPv4**（可在配置代理前从 VPS 运行 `curl -q -4 --noproxy '*' -fsS https://api.ipify.org` 确认），再将工具里的用户名留空。协议按订单填写；提供可校验证书的 HTTPS 代理时优先用 HTTPS。普通 HTTP 代理的账号密码在 VPS 至代理这一段没有 TLS 保护。[IPRoyal 认证说明](https://help.iproyal.com/en/articles/7955587-how-to-use-isp-proxies) · [Claude Code 代理设置](https://code.claude.com/docs/en/network-config#proxy-configuration)

在 VPS 的普通用户终端执行以下命令。原生安装器安装官方客户端，本卡附带的小工具为它加载当前用户的代理和令牌。已有官方原生安装可跳过第一行。[官方安装说明](https://code.claude.com/docs/en/setup#install-claude-code) · [查看小工具源码](server-claude)

```bash
(set -o pipefail; curl -fsSL https://claude.ai/install.sh | bash)
"$HOME/.local/bin/claude" --version
mkdir -p "$HOME/.local/bin"
curl -fsSL https://raw.githubusercontent.com/andyleimc-source/proxy-notes/master/vps-claude-code/server-claude -o "$HOME/.local/bin/server-claude.download" &&
  install -m 700 "$HOME/.local/bin/server-claude.download" "$HOME/.local/bin/server-claude" &&
  rm "$HOME/.local/bin/server-claude.download"
"$HOME/.local/bin/server-claude" configure-proxy
"$HOME/.local/bin/server-claude" exit-ip
```

看到版本号，且工具下载成功后再配置。按提示分开填协议、主机、端口、代理用户名和密码，工具会处理密码中的特殊字符。配置仅存本机 `~/.config/server-claude/`，目录权限 700，文件 600。工具在缺配置时会停止，支持代理的子进程会继承设置，SSH 及系统服务沿用原配置。未购买代理而选择 VPS 直连时，跳过这个工具及代理检测，直接按官方文档使用 `claude auth login`。

要让平时输入的 `claude` 也走这里，将以下两行放进**这台 VPS** 的 `~/.bashrc`（用 zsh 则是 `~/.zshrc`），打开新 SSH 窗口。在定时任务或非交互脚本中直接写 `"$HOME/.local/bin/server-claude"`，因为此类 shell 通常不加载别名。

```bash
alias claude='"$HOME/.local/bin/server-claude"'
alias cc='"$HOME/.local/bin/server-claude"'
```

## 4. 先验网络，再授权

- [ ] 新开 SSH，运行 `type claude`，应看到指向小工具的别名。运行 `claude exit-ip`，与订单的出口 IPv4 逐位对照；再用 `tmux new -s coding` 打开新终端，重复检查。若显示 VPS 原公网地址，先排查终端用的命令和订单，再做授权。
- [ ] 若要测浏览器，个人电脑使用临时独立浏览器配置。下例适用于订单提供 **HTTP 代理端点** 的情况。在个人电脑执行 SSH 转发，将 PROXY_HOST 和 PROXY_PORT 换成订单的代理端点，保留此 SSH 窗口。随后在另一个本机窗口运行下列 macOS Chrome 命令。Linux 用 `google-chrome` 替换可执行文件路径。浏览器弹出代理认证时输入自己的订单凭据。HTTPS 代理需保留供应商主机名并校验证书，按商家提供的 HTTPS 浏览器接入方式配置。
- [ ] 在同一个临时窗口先打开 ipify，确认显示订单出口，再打开两张完整检测页，记下出口、DNS 解析器、WebRTC 是否出现额外公网地址、日期。完成后退出该窗口并在 SSH 转发窗口按 Ctrl+C。[出口 IP](https://api.ipify.org/) · [Net.Coffee 完整检测](https://ip.net.coffee/claude/) · [1ms 完整检测](https://who.1ms.dog/zh-cn/)

```bash
ssh -p PORT -i ~/.ssh/claude-vps -N -o ExitOnForwardFailure=yes -L 127.0.0.1:18888:PROXY_HOST:PROXY_PORT USER@SERVER
```

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --user-data-dir="$(mktemp -d)" --proxy-server="http://127.0.0.1:18888" \
  https://api.ipify.org/
```

浏览器检测只反映打开页面的那个浏览器。实测曾有两个页面对同一个出口分别给出 84 分和 F 级；其中一页将解析器标为西班牙，两页当次均未显示额外的 WebRTC 公网地址。独立 DNS 对照出现过新加坡解析器；日常 Claude Code 的 DNS 地点仍未证实。以上结果均不代表 Claude 的账号审核结论。IPQS 是独立的 IP 信誉服务，当时其免费页面已达每日额度，未能复核供应商的零分标注。

如需核实 Claude 进程的流量，可在 IPRoyal 的该订单打开 **Data Usage Report**，选日期、分配的出口 IP 和目标域名 `api.anthropic.com`，记下基线、时区和时间。用日常入口运行一次 `claude doctor`，返回后按相同筛选再导出。商家当时提示入账可能延迟 24 小时；0.01 MB 这样的汇总显示无法区分很小的增量或同时段其他进程，也不提供 DNS 路径证据。[用量报表说明](https://help.iproyal.com/en/articles/7955587-how-to-use-isp-proxies)

## 5. 用自己的订阅授权，开始使用

1. 本人先在 Claude 账户的套餐页确认订阅已生效。在刚验过的 VPS 终端执行 `claude setup-token`，保持该终端等待。只打开本次生成的官方授权链接，用订阅所属账号完成授权。网页若显示一次性短码，就把它填回这个等待中的终端。
2. 授权成功后，终端会另行打印长期令牌。复制完整值**一次**，在另一条 VPS SSH 会话执行 `"$HOME/.local/bin/server-claude" save-token`，在隐藏输入提示下粘贴。工具会拒绝短码、带空格或重复拼接的令牌。长期令牌有效期一年，使用仍取决于订阅权益；订阅、代理和服务器各有自己的续费日。[官方长期令牌说明](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token)
3. 新开 SSH 并执行 `claude auth status --json`。本次实机的三个字段为 `loggedIn: true`、`authMethod: oauth_token`、`apiProvider: firstParty`。这一步检查 CLI 识别的认证方式。愿意使用订阅额度时，再进入自己的项目目录执行 `cc`，发一句“只回复 OK”，看到回复后才勾选真实对话通过。
4. 平时在项目目录启动 `cc`。tmux 中按 Ctrl+B 再按 D 可断开并保留终端，回来运行 `tmux attach -t coding`。代理到期或换密码时重新运行 `configure-proxy`，令牌到期重新走第 1、2 步，启动新会话并复验。

| 遇到什么 | 下一步 |
| --- | --- |
| SSH 拒绝公钥 | 从商家控制台核对用户名、公钥文件权限及 `sshd -T` 的实际配置，保留当前可用会话。 |
| 出口检查失败或代理返回 407 | 核对协议、端口、用户名密码、白名单来源及订单是否有效；重新运行 `configure-proxy`。普通 SSH 能连通只说明管理链路可用。 |
| 浏览器出口和订单不符 | 确认打开的是临时配置窗口、SSH 转发仍运行且端点正确。只在查到订单出口的窗口读取检测结果。 |
| CLI 仍提示登录或账单来源异常 | 先用 `type claude` 核对入口，确认在同一 Linux 用户下保存了令牌。检查是否另设了 API key、云服务认证或自定义接口，避免误用另一个付费账号。不要把令牌放进命令行或发给协助的人。 |
| 只有走代理的 Git 拉取失败 | 在 Git **已经走该代理**的环境，用 `git -c http.proxyAuthMethod=basic ls-remote <仓库HTTPS地址>` 做单次对照。若低内存机继承了异常大的 `http.postBuffer`，用 `git config --show-origin --get http.postBuffer` 查来源；原实机将本机覆盖值调到 1048576 后恢复。 |

## 交付时只回这几项

- [ ] 新窗口公钥 SSH、sudo 和 tmux 重连均通过。
- [ ] 启用固定代理时，SSH 新终端和 tmux 中的 `claude exit-ip` 都与自己的订单一致。
- [ ] 需要浏览器检测时，两页结果均来自已确认出口的独立窗口。
- [ ] 重新登录 SSH 后，官方 CLI 显示已认证，账号归属和付费方式正确。
- [ ] 真实对话：通过 / 暂未测试。到期提醒：服务器、固定 IP、Claude 订阅、长期令牌各自登记。

协助时分享勾选结果和删去个人信息的报错即可。订单页面、含 IP 的截图、授权链接、一次性短码、长期令牌、代理密码和 SSH 私钥留在自己的设备。
