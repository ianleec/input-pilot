# 简繁随行 1.1.0 安装包

构建日期：2026-11-09。架构：arm64 + x86_64 Universal。最低构建目标：macOS 13。

产物：

| 项目 | 精确大小 | 十进制近似 |
| --- | ---: | ---: |
| App 全部文件合计 | 1,262,412 bytes | 1.26 MB |
| DMG 安装镜像 | 1,382,456 bytes | 1.38 MB |
| ZIP 备用分发包 | 976,934 bytes | 0.98 MB |

App 磁盘分配由 `du -sh` 报告约 1.2M，可能因文件系统块大小、扩展属性而变化；上表 App 大小为文件逻辑大小合计。DMG 文件系统容量与压缩后的实际下载大小是不同概念。

产物目录：`build/releases/1.1.0/`。

SHA-256：

```text
8f3ec3715601152fca1e48aeb19192f7a388e3873e887fa1d41066586a8dd209  PinyinPilot-1.1.0-universal.dmg
073b50ba1ef54e43536abcfbbc1f0ed60ac0047a051b3320a5379d16c14c2de8  PinyinPilot-1.1.0-universal.zip
```

新增：完整多尺寸 App 图标、1.1.0 版本信息、关于面板、重复打开时恢复设置窗口、DMG 的 Applications 安装入口、中文安装说明和可复现打包脚本。

验证：

- 两架构交叉编译成功，`lipo -archs` 确认 `x86_64 arm64`。
- App 严格签名验证通过；DMG 校验通过。
- 实际只读挂载 DMG，确认 Applications 链接指向 `/Applications`。
- 在挂载镜像中的 App 直接执行规则／存储自检和网络沙盒检查，均 PASS。
- 从 DMG 复制 App 到本机 `~/Applications/PinyinPilot.app`，卸载镜像后启动成功；窗口显示 Discord 原有繁体规则，配置保留。
- 本机旧 1.0.1 备份于 `build/PinyinPilot-1.0.1-backup.zip`。

签名为本机 ad-hoc，未做 Developer ID 签名／公证。当前没有有效开发者签名证书。其他 Mac 首次打开可能需要通过系统“隐私与安全性”确认来源；不是已公证的公众发行版。Intel 与 macOS 13 未进行真机运行验收。
