.PHONY: generate build test run release scan clean

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

## Fail loudly if anything token-shaped is about to be committed.
scan:
	@./Scripts/scan-secrets.sh

clean:
	rm -rf build DerivedData Cleared.xcodeproj
