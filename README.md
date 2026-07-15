# macos-displayctl

A small command-line utility for enabling and disabling displays on macOS. It dynamically resolves the private CoreGraphics API `CGSConfigureDisplayEnabled` and applies changes only to the current login session.

## Requirements

- macOS
- Xcode Command Line Tools
- `make`

## Build

```bash
make
```

Other build targets:

```bash
make clean
make rebuild
```

## Usage

List online displays:

```bash
./displayctl list
```

Disable all online external displays:

```bash
./displayctl off
```

Restore the external displays previously disabled by the tool:

```bash
./displayctl on
```

Operate on a specific `CGDirectDisplayID`:

```bash
./displayctl off 2
./displayctl on 2
```

The default `off` command stores disabled external display IDs in `/tmp/displayctl-disabled-<uid>`, allowing the default `on` command to restore displays that no longer appear in the online display list.

The tool allows disabling the built-in display by ID only when at least one active external display will remain:

```bash
./displayctl off 1
./displayctl on 1
```

Display IDs can change after a restart, reconnection, or port change. Run `./displayctl list` before operating on a specific ID.

## Limitations

- This project uses a private, undocumented macOS API and may stop working after a system update.
- Display changes use `kCGConfigureForSession` and are not intended to persist across logout or restart.
- Restoring external displays with the default `on` command requires that they were previously disabled with the default `off` command.
- The utility has been tested only on the author's local macOS configuration.

## License

No license has been specified yet.
