# Input Pilot 开发说明

## 分支

- `main`：已构建、验收的稳定基线。
- `codex/input-pilot-development`：日常开发集成分支。
- 后续独立功能使用 `codex/<功能名>`；完成验证后通过 PR 合入目标分支。

## 开发与验证

使用 macOS 和 Apple Command Line Tools：

```bash
bash build.sh
"build/Input Pilot.app/Contents/MacOS/InputPilot" --self-test
"build/Input Pilot.app/Contents/MacOS/InputPilot" --privacy-test
codesign --verify --strict "build/Input Pilot.app"
```

涉及输入法调度时，额外执行 README 中的真实应用切换和最小化回归测试。测试期间暂勿操作前台应用，测试报告留在本机沙盒，不提交 Git。

## 隐私约束

不得引入遥测、上传、网络更新检查、按键监听、输入内容采集或云同步。App 必须保留沙盒且无网络权限。仅存储应用规则及输入源配置。

安装包和构建缓存由 `build/` 忽略；不得提交凭据、签名证书或个人规则。Bundle ID 沿用历史标识，以兼容已有本地配置。修改之前须提供迁移方案。

当前产物为本地 ad-hoc 签名；Developer ID 签名与公证仍待配置。编译通过不等于 Intel 或旧 macOS 版本已完成真机验证。
