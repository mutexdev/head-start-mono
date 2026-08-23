# Headstart iOS. The Xcode project is generated; always regenerate before building.
SIM ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5
DD  ?= build/DerivedData

.PHONY: project test fonts clean

## Regenerate Headstart.xcodeproj from project.yml.
project:
	xcodegen generate

## Regenerate, then build and run the unit tests on the simulator.
test: project
	xcodebuild -project Headstart.xcodeproj -scheme Headstart \
		-destination '$(SIM)' -derivedDataPath $(DD) test

## Generate the four static Archivo faces into Headstart/Fonts.
fonts:
	bash scripts/make-fonts.sh

clean:
	rm -rf $(DD) Headstart.xcodeproj
