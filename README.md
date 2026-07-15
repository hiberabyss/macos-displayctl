# DisplayCtl

`DisplayCtl` 是一个用于控制 macOS 显示器的开源工具，包含原生菜单栏应用和 `displayctl` 命令行程序。它通过动态解析 CoreGraphics 私有 API `CGSConfigureDisplayEnabled`，在当前登录会话中启用或禁用显示器。

## 功能

- 在 macOS 菜单栏中常驻，不显示 Dock 图标。
- 点击菜单栏图标后显示内置屏和外接屏列表。
- 每台显示器旁提供独立开关，可直接启用或禁用。
- 记住由应用关闭的显示器，使离线显示器仍可在列表中恢复。
- 仅当至少保留一台活动外接显示器时，才允许关闭内置屏。
- 保留命令行工具，支持脚本和自动化场景。

## 环境要求

- macOS 13 或更高版本
- Xcode Command Line Tools
- `make`

如未安装 Xcode Command Line Tools，请执行：

```bash
xcode-select --install
```

## 下载与安装

从 [GitHub Releases](https://github.com/hiberabyss/macos-displayctl/releases) 下载最新的 DMG，打开后将 `DisplayCtl.app` 拖入 `Applications`。

当前安装包使用临时签名，尚未通过 Apple Developer ID 签名和公证。如果 macOS 阻止首次启动，请在 Finder 中右键应用并选择“打开”，或前往“系统设置 → 隐私与安全性”确认打开。

## 编译菜单栏应用

```bash
git clone https://github.com/hiberabyss/macos-displayctl.git
cd macos-displayctl
make app
```

应用会生成在：

```text
build/DisplayCtl.app
```

直接编译并启动：

```bash
make run
```

安装到 `/Applications`：

```bash
make install
```

生成版本化 DMG 安装包：

```bash
make dmg
```

DMG 会生成在 `build/` 目录中，版本号来自 `Info.plist`。

安装后可从“应用程序”目录启动。启动成功后，菜单栏会出现显示器图标。点击图标即可查看显示器列表，并通过每行右侧的开关控制屏幕状态。

## 编译命令行工具

```bash
make cli
```

不指定目标时，会同时编译命令行工具和菜单栏应用：

```bash
make
```

其他构建命令：

```bash
make clean
make rebuild
```

## 命令行用法

列出所有在线显示器：

```bash
./displayctl list
```

示例输出：

```text
1    built-in    active    1728x1117
2    external    active    1920x1080
```

关闭所有在线外接显示器：

```bash
./displayctl off
```

恢复此前由默认 `off` 命令关闭的外接显示器：

```bash
./displayctl on
```

使用 `CGDirectDisplayID` 控制指定显示器：

```bash
./displayctl off 2
./displayctl on 2
```

重新启动 macOS、重新连接显示器或更换接口后，显示器 ID 可能变化。按 ID 操作前，请先运行 `./displayctl list`。

## 安全机制

菜单栏应用和命令行程序均使用 `kCGConfigureForSession` 提交显示器配置，变更仅针对当前登录会话。关闭内置屏前，程序会确认至少还有一台活动外接显示器，避免关闭唯一可用的屏幕。

菜单栏应用会在用户偏好设置中保存由它关闭的显示器信息，以便显示器从在线列表消失后仍可重新开启。命令行工具则将外接屏 ID 临时记录在 `/tmp/displayctl-disabled-<uid>` 中。

## 限制与警告

本项目使用未公开且没有正式文档的 macOS 私有 API `CGSConfigureDisplayEnabled`。Apple 可能随时修改或移除该 API，因此工具可能在 macOS 更新后失效，也不适合提交到 Mac App Store。

显示配置原则上不会在注销或重启后继续生效，但私有 API 的行为无法得到保证。请自行承担使用风险。本工具仅在有限的 macOS 设备和显示器配置上测试过。

## 许可证

本项目采用 MIT 许可证，详情请参阅 [LICENSE](LICENSE)。
