# proxy-notes

代理（Clash / VPN）相关的配置问题与解决方案备忘。遇到一个记一个，主要自用，公开分享。

环境：macOS + Clash Verge（mihomo 内核）为主。

## 目录

| 问题 | 文档 |
|------|------|
| Apple 地图 Mac 版「路线不可用」——代理把定位/路线请求发到境外 | [apple-maps-route-unavailable.md](apple-maps-route-unavailable.md) |

## 通用心智

- **地图瓦片能加载但路线/定位失败** → 多半是某个 Apple/服务域名被代理发到了境外后端，把对应域名加 `DIRECT` 直连即可。
- **Clash Verge 改规则不想动订阅** → 用订阅挂着的「rules / merge 覆写」文件加 `prepend`，订阅更新不会被覆盖。
- 改完磁盘上的配置文件后，**必须在 Clash Verge UI 重新选中一次订阅**才会重新合并并重启内核生效。
