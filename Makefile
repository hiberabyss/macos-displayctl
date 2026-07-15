CC := xcrun clang
SWIFTC := xcrun swiftc
CFLAGS := -Wall -Wextra -Werror -O2
LDLIBS := -framework ApplicationServices -framework CoreGraphics
SWIFTFLAGS := -O -parse-as-library -framework AppKit -framework CoreGraphics

CLI_TARGET := displayctl
CLI_SOURCE := displayctl.c
APP_NAME := macos-displayctl
APP_BUNDLE := build/$(APP_NAME).app
APP_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
APP_SOURCE := DisplayCtlApp.swift

.PHONY: all cli app run install clean rebuild

all: cli app

cli: $(CLI_TARGET)

$(CLI_TARGET): $(CLI_SOURCE)
	$(CC) $(CFLAGS) $(CLI_SOURCE) $(LDLIBS) -o $(CLI_TARGET)

app: $(APP_EXECUTABLE)

$(APP_EXECUTABLE): $(APP_SOURCE) Info.plist
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	$(SWIFTC) $(SWIFTFLAGS) $(APP_SOURCE) -o $(APP_EXECUTABLE)
	codesign --force --sign - $(APP_BUNDLE)

run: app
	open $(APP_BUNDLE)

install: app
	ditto $(APP_BUNDLE) /Applications/$(APP_NAME).app

clean:
	rm -rf $(CLI_TARGET) build

rebuild: clean all
