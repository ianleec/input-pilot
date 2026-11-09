# Input Pilot

当前版本 1.1.1。原名“简繁随行 / PinyinPilot”；应用名称、窗口、菜单、图标和安装包已更名。为保留现有配置，Bundle ID、沙盒目录及源码工程目录继续沿用旧标识。最新发布数据见 `RELEASE-1.1.1.md`。

macOS 原生菜单栏应用。根据前台应用的 Bundle ID 选择 Apple 简体／繁体拼音。**未配置应用默认简体拼音**，删除规则即恢复默认。

## 使用

本机安装位置：`/Users/siyanli/Applications/Input Pilot.app`。

1. 启动应用，打开“应用规则与输入法设置”。
2. 选择“繁体拼音”或“简体拼音”，点击“添加应用…”，选择一个或多个 `.app`。
3. 表格选中规则后，可以使用旁边的输入法选择器并点击“修改所选规则”，或点击“删除所选规则”。同一应用再次添加会更新已有规则。
4. 切到目标应用后通常约 0.3 秒完成首次选择与确认；前 1.3 秒有有限次数校验重试，处理系统延迟恢复输入法。快速切换只处理最后一个前台应用。
5. 关闭窗口后菜单栏“IP”继续运行；菜单可暂停、恢复、打开设置或退出。退出后停止自动切换。

无需辅助功能、录屏、输入监控权限。没有自动开启登录启动；需要时可由用户在系统“登录项”中加入应用。

macOS 必须先启用对应输入法。本机已确认存在 `com.apple.inputmethod.SCIM.ITABC` 与 `com.apple.inputmethod.TCIM.Pinyin`。缺失时先在系统设置 → 键盘 → 输入法中添加，随后点“刷新已启用输入法”。如系统自己的“自动切换到文稿的输入法”与规则冲突，请关闭该选项。

规则以应用为粒度，无法区分同一浏览器的不同网站、标签页或不同窗口。工具自身设置窗口不触发切换，以免配置时干扰输入。激活后前 1.3 秒内规则优先，之后手动更换输入法可以保持到下次前台应用变化。

1.0.1 加强后台稳定性：设置窗口关闭／最小化不影响监听；启用期间使用允许系统正常睡眠的 activity 防止 App Nap 延迟；每 0.5 秒仅检查前台进程 ID 变化，补漏激活事件；在激活后有限重试，全部校验激活代次与当前进程，避免快速切换时旧任务干扰新应用。暂停时释放 activity 并取消待执行切换。此检测不读取窗口或输入内容。

## 隐私与实现

- 纯 Swift + AppKit + Carbon，零第三方依赖、零服务端、零遥测、零更新检查。
- 通过 `NSWorkspace.didActivateApplicationNotification` 接收应用激活事件；使用 TIS 系统接口选择输入源。
- 不监听键盘、不采集输入文本、不读取剪贴板或窗口标题、不调用 AppleScript。
- 开启 App Sandbox；签名权限仅有沙盒和“用户选择文件只读”，用于选择 `.app` 并读取其名称与 Bundle ID。
- **没有网络客户端、网络服务端、Apple Events 或例外权限。** 系统沙盒拒绝出站连接；`--privacy-test` 实测本地回环 socket 返回 `EPERM`，没有发送任何用户数据。
- 配置保存在沙盒 `UserDefaults`，无 iCloud 或云同步功能。应用不会接收或上传打字内容。本声明针对本工具；系统输入法及其他软件的网络行为由其各自控制。
- 配置路径：`~/Library/Containers/local.siyanli.PinyinPilot/Data/Library/Preferences/local.siyanli.PinyinPilot.plist`。应用自身保存的配置仅含启用状态、输入源 ID、应用名称与规则；系统文件面板还会保存本地界面偏好。
- 只在当前用户会话运行，无管理员权限、后台守护程序或 LaunchAgent。

## 构建与验证

使用本机 Command Line Tools，无需下载包：

```bash
bash build.sh
"build/Input Pilot.app/Contents/MacOS/InputPilot" --list-sources
"build/Input Pilot.app/Contents/MacOS/InputPilot" --self-test
"build/Input Pilot.app/Contents/MacOS/InputPilot" --privacy-test
open "build/Input Pilot.app"
```

1.1.0 构建产物为 arm64 + x86_64 Universal App；最低构建目标 macOS 13。采用本机 ad-hoc 签名并包含沙盒 entitlements，尚未进行 Developer ID 签名、公证。只在当前 Apple Silicon Mac 验证运行，Intel 和旧版系统尚未真机验证；其他 Mac 首次安装可能需要在系统“隐私与安全性”中手动确认可信来源。

生成可拖拽安装的 DMG 和备用 ZIP：

```bash
bash package.sh
```

产物位于 `build/releases/1.1.1/`。DMG 包含 App、Applications 快捷入口及中文安装说明。应用有完整多尺寸图标与菜单栏“关于”窗口；再次打开已运行的应用会恢复设置窗口。更新时先退出旧版本，再替换 App，原配置保留。

真实应用切换集成测试（执行前退出其他 Input Pilot 实例，需要 Finder 和 Terminal 或 Safari 已运行）：

```bash
open -n "build/Input Pilot.app" --args --integration-test
```

此测试临时添加 Finder 繁体规则，验证默认简体 → Finder 繁体 → 默认简体 → 删除 Finder 规则后的简体。测试规则不落盘，结束恢复原配置、前台应用、输入法并退出。结果位于沙盒 `Data/Library/Application Support/PinyinPilot-integration.json`。

Discord／微信最小化回归（两应用需已运行，先退出其他 Input Pilot 实例）：

```bash
open -n "build/Input Pilot.app" --args --minimized-regression
```

自动最小化工具窗口，交替激活 Discord 和微信三轮，其中一轮在激活后 0.55 秒主动模拟系统覆盖输入法。逐阶段核对前台应用、输入源和实际最小化状态，任一不满足即失败。测试配置不落盘，结果保存在沙盒 `Data/Library/Application Support/PinyinPilot-minimized-regression.json`。测试会切换前台应用，请在测试期间暂勿操作。

## 已验证环境

2026-11-09，macOS 26.6.2 / Apple Silicon / Swift 6.3.3：

- 编译与签名成功。
- 默认简体、规则新增／去重更新／删除、本地编码与存储回读通过。
- 沙盒阻断联网通过。
- 真实 Finder／Terminal 激活通知及输入源切换通过。
- 原生设置窗口的规则增改、重启恢复和删除实测记录见 `VERIFICATION.md`。

移除：退出应用后将 `~/Applications/Input Pilot.app` 移入废纸篓。沙盒配置会保留，重新安装可恢复；需要清空时由用户另行移除该应用专属容器。源码与构建目录独立保留。
