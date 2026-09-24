# Clash Verge 只用 TUN：升级后排查残留系统代理

2026-09-24 在 work Mac（macOS 26.6.2，Clash Verge 2.5.5）实测：升级后出现“必须开系统代理才正常”的假象。实际是 TUN 已经工作，但 macOS 系统代理还开着，而且挂在有线网卡上。

## 结论

TUN 和 macOS 系统代理是两种独立的流量接管方式，不需要同时启用。TUN 已接管网络时，可以关闭系统代理。升级后如果遇到应用联网异常，先检查所有网卡上的系统代理状态，不要只看 Wi-Fi。

这台 work Mac 实际网络服务是 `AX88179A`（USB 有线网卡）；Wi-Fi 的系统代理本来就是关闭的。只关 Wi-Fi 不会改变实际有线网卡上的代理状态。

## 检查实际网络接口

```bash
networksetup -listallnetworkservices
route -n get 1.1.1.1
scutil --proxy
```

`route` 输出里的 `interface` 是到外网的路由接口。Clash TUN 的默认路由应指向某个 `utunN`。本次 work 为 `utun9`，并能看到 `198.18.0.0` 虚拟地址。

对实际联网的网络服务检查三类系统代理（把服务名换成自己的）：

```bash
networksetup -getwebproxy "AX88179A"
networksetup -getsecurewebproxy "AX88179A"
networksetup -getsocksfirewallproxy "AX88179A"
```

## 只保留 TUN

先在 Clash Verge 确认 TUN 模式已启用，然后关闭实际联网网卡的系统代理：

```bash
networksetup -setwebproxystate "AX88179A" off
networksetup -setsecurewebproxystate "AX88179A" off
networksetup -setsocksfirewallproxystate "AX88179A" off
```

如果机器有多个可能联网的接口，分别检查并关闭不需要的系统代理。再次运行 `scutil --proxy`，HTTP、HTTPS、SOCKS 应均为 `0`。

## 验证 TUN 独立工作

不要给 curl 指定 `-x` 或 socks 参数：

```bash
curl -sS --max-time 8 https://www.apple.com/library/test/success.html
route -n get 1.1.1.1
```

本次关完系统代理后 Apple HTTPS 请求仍成功，路由仍指向 `utun9`，确认 TUN 单独工作。

## 升级后注意

本次应用偏好文件仍保存 `enable_system_proxy: true`，但 macOS 的系统代理实际状态已关闭，且 TUN 独立验收通过。偏好记录和操作系统实际状态可能不一致。重启 Clash Verge 后应再次检查 `scutil --proxy` 和活动网卡代理开关，确认应用没有重新打开系统代理。
