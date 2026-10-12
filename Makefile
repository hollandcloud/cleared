.PHONY: generate build test run install preview icon release dist scan clean

RELEASE_APP := build/Build/Products/Release/Cleared.app
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
	@pkill -x Cleared 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/Cleared.app"
	ditto $(RELEASE_APP) "$(INSTALL_DIR)/Cleared.app"
	open "$(INSTALL_DIR)/Cleared.app"
	@echo "✓ Installed Cleared $$(defaults read "$(INSTALL_DIR)/Cleared.app/Contents/Info" CFBundleShortVersionString) to $(INSTALL_DIR)"

## Render the panel in a normal window against sample data.
## FIXTURE=full|overflow|empty
preview: build
	@pkill -f 'Cleared.app/Contents/MacOS/Cleared' 2>/dev/null || true
	@open "$$(xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration Debug \
		-showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $$3}')/Cleared.app" \
		--args --ui-preview $${FIXTURE:-full}

## Redraw the app icon at every size from Scripts/make-icon.swift.
icon:
	swift Scripts/make-icon.swift

## Build a Developer ID-signed, notarized zip in dist/. See Scripts/release.sh.
dist:
	@./Scripts/release.sh

## Fail loudly if anything token-shaped is about to be committed.
scan:
	@./Scripts/scan-secrets.sh

clean:
	rm -rf build dist DerivedData Cleared.xcodeproj
