# 页面化本地化源

本目录是 BatteryMonitor 内置界面文案的唯一编辑权威。分类原则是：

```text
页面 → 页面区块 → key
                    ↘ 真正跨页面的公共文案进入 shared/
                    ↘ 结构化字段数据进入 catalogs/
```

不要按“来自 HTML / 来自 SwiftUI”分类；两端读取同一批生成语言包。不要直接修改 `Localization/Languages/*.json`。

常用命令：

```bash
# 查询 key 的归属、中文/英文和代码引用
python3 Localization/build-language-packs.py find p.trend_fitted

# 从任意内置语言的界面文案反查 key、源文件和代码引用
python3 Localization/build-language-packs.py lookup-text "Stable estimate"

# 查看全部页面/区块及 key 数量
python3 Localization/build-language-packs.py list

# 修改 Sources 后生成十个运行时语言包
python3 Localization/build-language-packs.py write

# 只读验证源文件、格式符和生成产物
python3 Localization/build-language-packs.py check
```

每个 key 必须恰好提供 `manifest.json` 声明的十种非空译文。字面百分号写 `%%`；真实 C 格式符和 `{name}` 命名占位符必须与英文保持兼容。

完整规则见项目根目录 `LOCALIZATION.md`。
