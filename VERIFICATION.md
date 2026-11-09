# 验收记录

日期：2026-11-09。环境：本机 macOS 26.6.2，Apple Silicon。

| 需求 | 验证方式 | 结果 |
| --- | --- | --- |
| 本机可运行的小工具 | Swift 编译、ad-hoc 沙盒签名、安装后启动原生窗口及菜单栏 | 通过 |
| 未配置应用默认简体拼音 | 实际 Terminal 激活后读取 TIS 当前输入源 | `com.apple.inputmethod.SCIM.ITABC` |
| 繁体应用规则生效 | 临时配置 Finder 为繁体，实际激活 Finder | `com.apple.inputmethod.TCIM.Pinyin` |
| 来回切换应用 | Finder → Terminal，监听真实工作区激活通知 | 恢复简体 |
| 删除后恢复默认 | 删除 Finder 规则，再从 Terminal 激活 Finder | 简体 |
| 界面新增 | 系统文件选择器选 Finder.app，新增繁体规则 | 表格显示 Finder / com.apple.finder / 繁体拼音 |
| 界面修改 | 表格选中 Finder，选择简体并点击修改 | 表格更新为简体拼音 |
| 配置持久化 | 退出进程并重新打开已安装应用 | Finder 简体规则仍存在 |
| 界面删除 | 选中 Finder 点击删除 | 表格为空；测试规则已清理 |
| 模型及存储测试 | `--self-test`：默认、增改、去重、删除、编码、UserDefaults 回读 | PASS |
| 联网限制 | `--privacy-test` 尝试连接本地 127.0.0.1:9，无传输内容 | 系统返回 EPERM，PASS |
| 最终签名 | `codesign --verify --strict --verbose=2` | valid on disk；satisfies Designated Requirement |
| 权限核查 | `codesign -d --entitlements :-` | 仅 app-sandbox、files.user-selected.read-only；无网络权限 |

集成测试只将应用 ID、预期输入源与实际输入源写入本地沙盒报告，不记录输入文字或窗口标题。结果文件为 `~/Library/Containers/local.siyanli.PinyinPilot/Data/Library/Application Support/PinyinPilot-integration.json`。

验收范围：本机已启用的 Apple 简体拼音和繁体拼音；其他 macOS 版本、第三方输入法、系统重启后的登录启动、对外分发公证未声称已验证。登录启动和对外分发不属于本次要求。

## 1.0.1 最小化切换回归

2026-11-09 用户反馈：工具窗口最小化后 Discord → 微信偶发不切换。读取当前配置确认 Discord 为繁体，微信没有规则、应默认简体。原版多次能成功切换，未稳定复现用户失败场景；不能将 App Nap 或系统覆盖认定为已证实的唯一原因。源码证据：原版仅在激活后 0.18 秒选择一次，0.16 秒后仅检查、无重试；无前台进程漏事件检测或后台 activity。

修改：启用期间防 App Nap（仍允许系统闲置睡眠）；0.5 秒检测前台 PID 变化补漏；每次激活 0.12／0.4／0.8／1.3 秒有限次数尝试，均校验激活代次、进程和启用状态。暂停或换应用令旧回调失效。打开设置会恢复已最小化窗口。

验证：`--minimized-regression` 实际最小化窗口，按 Discord 繁体／微信默认简体交替三轮。每个检查点都确认 `windowMiniaturized=true`、前台应用匹配、TIS 输入源匹配。第二轮在激活后 0.55 秒主动选错输入法模拟系统覆盖，后续校验恢复目标输入法。六个检查全部通过，最终报告 `passed=true`。

首次回归因第一个检查点前台实际停在微信而失败；未据此认定通过。完整重跑确认六个目标应用均成功激活、所有检查点通过。真实用户环境的长期偶发稳定性仍需继续观察。

构建无警告；规则与本地存储自检、网络沙盒阻断复测通过。1.0.0 App 备份在 `build/PinyinPilot-1.0.0-backup.zip`。本次更新未改动用户持久化配置。

## 1.1.0 安装包验收

详见 `RELEASE.md`。DMG 实际挂载与校验通过，包内 App 自检与网络阻断通过。从镜像复制安装，卸载镜像后 App 1.1.0 成功启动并保留用户规则。App 文件总大小 1,262,412 bytes；DMG 1,382,456 bytes；ZIP 976,934 bytes。arm64 与 x86_64 两架构均构建完成，仅在本机 Apple Silicon 实测运行。
