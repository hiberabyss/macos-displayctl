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
APP_ICON := asset/AppIcon.icns
APP_VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG_NAME := $(APP_NAME)-$(APP_VERSION).dmg
DMG_PATH := build/$(DMG_NAME)
DMG_ROOT := build/dmg-root

.PHONY: all cli app dmg run install clean rebuild

all: cli app

cli: $(CLI_TARGET)

$(CLI_TARGET): $(CLI_SOURCE)
	$(CC) $(CFLAGS) $(CLI_SOURCE) $(LDLIBS) -o $(CLI_TARGET)

app: $(APP_EXECUTABLE)

$(APP_EXECUTABLE): $(APP_SOURCE) Info.plist $(APP_ICON)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp $(APP_ICON) $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	$(SWIFTC) $(SWIFTFLAGS) $(APP_SOURCE) -o $(APP_EXECUTABLE)
	codesign --force --sign - $(APP_BUNDLE)

dmg: app
	rm -rf $(DMG_ROOT) $(DMG_PATH)
	mkdir -p $(DMG_ROOT)
	ditto $(APP_BUNDLE) $(DMG_ROOT)/$(APP_NAME).app
	ln -s /Applications $(DMG_ROOT)/Applications
	hdiutil create -volname "$(APP_NAME) $(APP_VERSION)" -srcfolder $(DMG_ROOT) -ov -format UDZO $(DMG_PATH)
	rm -rf $(DMG_ROOT)

run: app
	open $(APP_BUNDLE)

install: app
	ditto $(APP_BUNDLE) /Applications/$(APP_NAME).app

clean:
	rm -rf $(CLI_TARGET) build

rebuild: clean all