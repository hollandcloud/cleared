.PHONY: generate build test run install preview icon release dist appstore appstore-build scan clean

RELEASE_APP := build/Build/Products/Release/GitCleared.app
INSTALL_DIR ?= /Applications

generate:            ## Regenerate Cleared.xcodeproj from project.yml
	xcodegen generate

build: generate
	xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration Debug build

test: generate
	xcodebuild -project Cleared.xcodeproj -scheme Cleared -destination 'platform=macOS' test

release: generate
	xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration Release \
		-derivedDataPath build clean build

run: release
	open $(RELEASE_APP)

## Build Release, replace the copy in /Applications, and launch it.
## Launch at login only works from an installed copy.
install: release
	@pkill -x GitCleared 2>/dev/null || true
	@# The app was called Cleared until 0.4.1. Take that copy away too, or
	@# two would be left watching the same queue.
	@pkill -x Cleared 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/GitCleared.app" "$(INSTALL_DIR)/Cleared.app"
	ditto $(RELEASE_APP) "$(INSTALL_DIR)/GitCleared.app"
	open "$(INSTALL_DIR)/GitCleared.app"
	@echo "✓ Installed GitCleared $$(defaults read "$(INSTALL_DIR)/GitCleared.app/Contents/Info" CFBundleShortVersionString) to $(INSTALL_DIR)"

## Render the panel in a normal window against sample data.
## FIXTURE=full|overflow|empty
## Opens a second instance and only ever closes an earlier preview, so an
## installed copy that is running keeps watching.
preview: build
	@pkill -f 'GitCleared.app/Contents/MacOS/GitCleared --ui-preview' 2>/dev/null || true
	@open -n "$$(xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration Debug \
		-showBuildSettings 2>/dev/null | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p')/GitCleared.app" \
		--args --ui-preview $${FIXTURE:-full}

## Redraw the app icon at every size from Scripts/make-icon.swift.
icon:
	swift Scripts/make-icon.swift

## Build a Developer ID-signed, notarized zip in dist/. See Scripts/release.sh.
dist:
	@./Scripts/release.sh

## Archive for the Mac App Store and export the signed package to
## dist/appstore/. Uploads nothing. See Scripts/appstore.sh.
appstore:
	@./Scripts/appstore.sh

## Build the sandboxed App Store configuration without archiving. Works with
## no signing set up, so CI uses it to keep that configuration compiling.
appstore-build: generate
	xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration AppStore \
		-derivedDataPath build/appstore build

## Fail loudly if anything token-shaped is about to be committed.
scan:
	@./Scripts/scan-secrets.sh

clean:
	rm -rf build dist DerivedData Cleared.xcodeproj
