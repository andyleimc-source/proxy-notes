# Apple 地图 Mac 版「路线不可用」

## 症状

Apple 地图（Mac app）地图瓦片正常加载，但规划路线时提示 **「路线不可用 / 从此位置出发的路线不可用」**。

## 原因

开了代理（Clash 等）后，Apple 地图的**定位 / 路线服务请求被发到了境外出口**。中国大陆的 Apple 地图路线由高德提供后端，请求必须从国内出口发出，走境外会被拒绝 —— 于是瓦片能看、路线规划不出来。

## 解决：把 Apple 地图相关域名设为直连（DIRECT）

核心域名（`ls.apple.com` 已覆盖所有 `gsp*` / `gspe*` 定位与路线子域）：

```yaml
- "DOMAIN-SUFFIX,ls.apple.com,DIRECT"
- "DOMAIN-SUFFIX,apple-mapkit.com,DIRECT"
- "DOMAIN-SUFFIX,apple-mapkit.com.cn,DIRECT"
- "DOMAIN-SUFFIX,gsp-ssl.apple.com,DIRECT"
- "DOMAIN-SUFFIX,gateway.icloud.com,DIRECT"
```

### Clash Verge 具体操作（不动订阅）

1. 找到当前订阅挂着的 **rules 覆写文件**。macOS 路径：
   ```
   ~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/
   ```
   在 `profiles.yaml` 里找到当前 `current:` 对应的 remote 订阅，它的 `option.rules` 字段指向那个覆写文件（如 `rgOUKmXiRJFu.yaml`）。
2. 把上面的规则填进该文件的 `prepend:` 列表：
   ```yaml
   prepend:
     - "DOMAIN-SUFFIX,ls.apple.com,DIRECT"
     - "DOMAIN-SUFFIX,apple-mapkit.com,DIRECT"
     - "DOMAIN-SUFFIX,apple-mapkit.com.cn,DIRECT"
     - "DOMAIN-SUFFIX,gsp-ssl.apple.com,DIRECT"
     - "DOMAIN-SUFFIX,gateway.icloud.com,DIRECT"
   append: []
   delete: []
   ```
   > 也可以在 Clash Verge UI 里新建一个「全局扩展配置（Merge）」用 `prepend-rules` 写同样的规则，效果一样。
3. **在 Clash Verge「订阅」页重新选中一次当前订阅**（或点刷新/重新应用），让它重新合并配置并重启内核。磁盘改动不重选不生效。

## 验证

重新选中订阅后，打开地图 App 重新规划路线，同时看 Clash Verge **「连接」页**搜 `apple`：
- `ls.apple.com` 的连接走 **DIRECT** → 成功，路线能出来了。
- 仍走代理 → 覆写没生效，检查规则文件路径和订阅是否真的重选过。

## 还不行？大概率是 TUN + DNS 污染

TUN 模式下若 DNS 被污染，可在 DNS 配置里给这些域名加 `fake-ip-filter` 或指定国内 DNS 解析。（遇到再补具体配置。）
