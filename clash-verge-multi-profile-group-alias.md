# Clash Verge 多订阅切换：策略组名不匹配（Proxy vs Proxies）校验报错与别名解法

> 适用场景：macOS / Windows + Clash Verge Rev（mihomo 内核），开着全局 Merge 规则覆写时，导入/切换不同机场订阅遇到报错。

---

## 症状

在 Clash Verge Rev 中配置了全局扩展规则（`Merge.yaml`，如白名单模式或自定义分流），规则里指定了目标代理组为 `Proxy`（如 `DOMAIN-SUFFIX,github.com,Proxy` 或 `MATCH,Proxy`）。

当切换到新机场（如 LinkCube / 部分专线机场）时，点击订阅报错并撤销变更：

```text
level=error msg="rules[0] [DOMAIN-SUFFIX,alternativeto.net,Proxy] error: proxy [Proxy] not found" configuration file .../clash-verge-check.yaml test failed
```

如果尝试直接在订阅的原始 yaml 文件里手动加上 `Proxy` 组，同时又在增强配置里加了，则会报：

```text
level=error msg="ProxyGroup Proxy: duplicate group name" configuration file .../clash-verge-check.yaml test failed
```

---

## 根本原因

1. **机场主组名差异**：
   - 常见老订阅/自建节点：主策略组通常叫 `Proxy`。
   - 部分机场（如 LinkCube 等）：主策略组叫 `Proxies`（多了个 s），或 `🚀 节点选择`、`PROXIES` 等。
2. **校验机制**：
   - Clash Verge 在切换订阅时，会把全局 `Merge.yaml` 的规则合并进去，并调用 mihomo 内核预校验（`verge-mihomo -t`）。
   - 规则里写着走 `Proxy`，但新订阅只有 `Proxies`，内核找不到名为 `Proxy` 的组，判定配置非法直接阻断。
3. **不能改全局 Merge**：
   - 如果把全局 Merge 里的 `Proxy` 改成 `Proxies`，切换回原机场时原机场又会报错。

---

## 最佳解法：订阅专属「策略组别名注入」

**原则**：不改全局 Merge 规则，不手改订阅原始下载文件（否则订阅更新就会被覆盖），利用 Clash Verge Rev 的**单订阅 Groups 扩展模板**自动挂载别名。

### 操作步骤

1. 打开 Clash Verge Rev 客户端，点击左侧 **「订阅」**。
2. 找到报错的新机场订阅卡片，**右键**点击卡片，选择 **「编辑扩展」**（或编辑信息 -> 策略组 / Groups）。
3. 在打开的配置模板中，在 `prepend`（前置注入）中加入一个名为 `Proxy` 的选择组，指向新机场的实际主组名（如 `Proxies`）：

```yaml
# Profile Enhancement Groups Template for Clash Verge

prepend:
  - name: Proxy
    type: select
    proxies:
      - Proxies
      - DIRECT

append: []

delete: []
```

4. 保存后，再次点击该订阅卡片激活。

---

## 为什么这是最优解

1. **防覆盖**：这是挂在当前订阅下的独立配置（位于 `$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/<uid>.yaml`），即使点击「更新订阅」拉取最新节点，也不会被覆盖。
2. **两全其美**：
   - 切换到新机场时：自动前置 `Proxy` 组并转发给 `Proxies`，全局 Merge 规则无缝生效。
   - 切换回老机场时：老机场不受影响，走老机场自带的 `Proxy` 组。
3. **避免重复组名报错**：不要在原始订阅 yaml 里手动黏贴，只在 Groups 模板的 `prepend` 中定义一次即可，绝对不会出现 `duplicate group name`。
