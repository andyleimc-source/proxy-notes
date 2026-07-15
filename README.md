# proxy-notes

代理（Clash / VPN）相关的配置问题与解决方案备忘。遇到一个记一个，主要自用，公开分享。

环境：macOS + Clash Verge（mihomo 内核）为主。

## 目录

| 问题 | 文档 |
|------|------|
| Apple 地图 Mac 版「路线不可用」——代理把定位/路线请求发到境外 | [apple-maps-route-unavailable.md](apple-maps-route-unavailable.md) |
| 华硕路由器 fancyss 节点全 timeout（DNS 鸡生蛋 + 协议升级）+ Claude Code 远程切节点工具 | [asus-fancyss-router/](asus-fancyss-router/) |
| 订阅流量烧太快（兜底 MATCH,Proxy 黑名单）→ 白名单改造 runbook + Claude Code 终端登录 403 大坑（fake-ip 被 Tailscale MagicDNS 抢答） | [clash-verge-whitelist/](clash-verge-whitelist/) |

## 通用心智

- **地图瓦片能加载但路线/定位失败** → 多半是某个 Apple/服务域名被代理发到了境外后端，把对应域名加 `DIRECT` 直连即可。
- **Clash Verge 改规则不想动订阅** → 用订阅挂着的「rules / merge 覆写」文件加 `prepend`，订阅更新不会被覆盖。
- 改完磁盘上的配置文件后，**必须在 Clash Verge UI 重新选中一次订阅**才会重新合并并重启内核生效（无人值守场景可直接重启 App，效果相同）。
- **浏览器正常、终端 CLI 挂**（如 Claude Code 登录 403）→ 十有八九是终端流量进 TUN 时只剩裸 IP（fake-ip 被 Tailscale MagicDNS 等抢答），`DOMAIN-*` 规则匹配不上掉了兜底。给终端挂 `https_proxy=http://127.0.0.1:7897` 环境变量即解，详见 [clash-verge-whitelist/](clash-verge-whitelist/)。
- **兜底规则用 `MATCH,DIRECT`（白名单）还是 `MATCH,Proxy`（黑名单）** 决定了订阅流量消耗量级：黑名单模式下 Apple 更新、AWS CDN、各种软件后台流量都在偷偷烧代理流量。
