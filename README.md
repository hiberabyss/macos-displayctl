# macos-displayctl

`macos-displayctl` is a small command-line utility for enabling and disabling displays on macOS. It dynamically resolves the private CoreGraphics API `CGSConfigureDisplayEnabled` and applies display changes to the current login session.

## Features

- List online displays and their `CGDirectDisplayID` values.
- Disable and restore external displays with simple commands.
- Enable or disable a specific display by ID.
- Prevent the built-in display from being disabled unless an active external display remains available.
- Apply changes only to the current login session.

## Requirements

- macOS
- Xcode Command Line Tools
- `make`

Install the Xcode Command Line Tools if necessary:

```bash
xcode-select --install
```

## Build

Clone the repository and build the executable:

```bash
git clone https://github.com/hiberabyss/macos-displayctl.git
cd macos-displayctl
make
```

Additional build targets:

```bash
make clean
make rebuild
```

## Usage

List all online displays:

```bash
./displayctl list
```

Example output:

```text
1    built-in    active    1728x1117
2    external    active    1920x1080
```

Disable all online external displays:

```bash
./displayctl off
```

Restore the external displays previously disabled by the default `off` command:

```bash
./displayctl on
```

Enable or disable a specific display using its `CGDirectDisplayID`:

```bash
./displayctl off 2
./displayctl on 2
```

The built-in display can be disabled by ID only when at least one active external display will remain:

```bash
./displayctl off 1
./displayctl on 1
```

Display IDs may change after restarting macOS, reconnecting a display, or switching ports. Run `./displayctl list` before operating on a specific display ID.

## How Restoration Works

The default `off` command records the IDs of disabled external displays in `/tmp/displayctl-disabled-<uid>`. The default `on` command reads this file so that it can restore displays that no longer appear in the online display list.

Using `./displayctl on` requires the displays to have been disabled previously with `./displayctl off`. When operating directly by ID, use the same ID to restore the display.

## Limitations and Warning

This project uses the private, undocumented macOS API `CGSConfigureDisplayEnabled`. Apple may change or remove this API at any time, so the utility may stop working after a macOS update.

Display changes are committed with `kCGConfigureForSession`. They are not intended to persist after logout or restart, but behavior involving private APIs cannot be guaranteed. Use this utility at your own risk, and ensure that another usable display remains available before disabling the built-in display.

The utility has only been tested on a limited set of macOS hardware and display configurations.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
