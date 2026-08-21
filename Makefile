.PHONY: generate build test run preview release scan clean

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
	open build/Build/Products/Release/Cleared.app

## Render the panel in a normal window against sample data.
## FIXTURE=full|overflow|empty
preview: build
	@pkill -f 'Cleared.app/Contents/MacOS/Cleared' 2>/dev/null || true
	@open "$$(xcodebuild -project Cleared.xcodeproj -scheme Cleared -configuration Debug \
		-showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $$3}')/Cleared.app" \
		--args --ui-preview $${FIXTURE:-full}

## Fail loudly if anything token-shaped is about to be committed.
scan:
	@./Scripts/scan-secrets.sh

clean:
	rm -rf build DerivedData Cleared.xcodeproj
