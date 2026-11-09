# Input Pilot 1.1.1

2026-11-09 更名发布。App 文件名 `Input Pilot.app`，执行文件 `InputPilot`，菜单栏简称 `IP`，图标为 IP 与双向箭头。Bundle ID 保持 `local.siyanli.PinyinPilot` 以继续使用用户原有配置。

本机已安装启动：`/Users/siyanli/Applications/Input Pilot.app`。旧 App 已移动到 `build/PinyinPilot-1.1.0-before-rename.app` 备份，不在用户应用目录保留重复入口。

| 产物 | 字节数 | 约大小 |
| --- | ---: | ---: |
| App 全部文件 | 1,201,060 | 1.20 MB |
| Input-Pilot-1.1.1-universal.dmg | 1,250,635 | 1.25 MB |
| Input-Pilot-1.1.1-universal.zip | 875,482 | 0.88 MB |

安装包在 `build/releases/1.1.1/`。通用架构 arm64 / x86_64；本机临时签名，未做 Apple Developer ID 公证。

签名验证、规则及存储自检、网络沙盒检查通过；安装后原生窗口显示 Input Pilot 名称，Discord 的原有繁体规则保留。DMG 校验通过。

SHA-256：

```text
85cb3b27d26de284b6fe0c454fd7965afe53f7af7299b3dfea5716d23da9f32a  Input-Pilot-1.1.1-universal.dmg
149d3a2c6bb2f6218eb31a87156dffd47de7475d0724795a1324d4a574396a83  Input-Pilot-1.1.1-universal.zip
```
