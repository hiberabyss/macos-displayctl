# macos-displayctl

`macos-displayctl` 是一个用于在 macOS 上启用和禁用显示器的小型命令行工具。它会动态解析 CoreGraphics 私有 API `CGSConfigureDisplayEnabled`，并在当前登录会话中应用显示器配置变更。

## 功能

- 列出当前在线的显示器及其 `CGDirectDisplayID`。
- 通过简单命令关闭和恢复外接显示器。
- 按显示器 ID 启用或禁用指定显示器。
- 仅当至少保留一台活动外接显示器时，才允许关闭内置显示器。
- 显示器配置变更仅应用于当前登录会话。

## 环境要求

- macOS
- Xcode Command Line Tools
- `make`

如果尚未安装 Xcode Command Line Tools，可执行：

```bash
xcode-select --install
```

## 编译

克隆仓库并编译程序：

```bash
git clone https://github.com/hiberabyss/macos-displayctl.git
cd macos-displayctl
make
```

其他构建命令：

```bash
make clean
make rebuild
```

## 使用方法

列出所有在线显示器：

```bash
./displayctl list
```

示例输出：

```text
1    built-in    active    1728x1117
2    external    active    1920x1080
```

关闭所有在线的外接显示器：

```bash
./displayctl off
```

恢复此前由默认 `off` 命令关闭的外接显示器：

```bash
./displayctl on
```

使用 `CGDirectDisplayID` 启用或禁用指定显示器：

```bash
./displayctl off 2
./displayctl on 2
```

只有在操作后仍会保留至少一台活动外接显示器时，才能通过 ID 关闭内置显示器：

```bash
./displayctl off 1
./displayctl on 1
```

重新启动 macOS、重新连接显示器或更换接口后，显示器 ID 可能发生变化。按 ID 操作显示器前，请先运行 `./displayctl list` 确认当前 ID。

## 恢复机制

默认的 `off` 命令会将被关闭的外接显示器 ID 记录在 `/tmp/displayctl-disabled-<uid>` 中。默认的 `on` 命令会读取该文件，从而恢复已经不再出现在在线显示器列表中的显示器。

使用 `./displayctl on` 恢复外接显示器，要求这些显示器此前由 `./displayctl off` 关闭。如果直接按 ID 操作，请使用相同的 ID 恢复显示器。

## 限制与警告

本项目使用了未公开且没有正式文档的 macOS 私有 API `CGSConfigureDisplayEnabled`。Apple 可能随时修改或移除该 API，因此本工具可能在 macOS 系统更新后失效。

显示器配置通过 `kCGConfigureForSession` 提交，原则上不会在注销或重启后继续生效，但私有 API 的行为无法得到保证。请自行承担使用风险，并在关闭内置显示器前确保至少还有一台可用的外接显示器。

本工具仅在有限的 macOS 设备和显示器配置上进行过测试。

## 许可证

本项目采用 MIT 许可证，详情请参阅 [LICENSE](LICENSE)。
