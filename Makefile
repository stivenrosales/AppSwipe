# Makefile — app-swipe
#
# macOS 26 Tahoe CLT workaround:
# The CLT's libPackageDescription.dylib has a symbol mismatch with its .swiftinterface
# (SwiftVersion typealias vs SwiftLanguageMode). A swiftc wrapper injects a linker alias
# to bridge the gap. The Testing.framework and lib_TestingInterop.dylib are also not in
# the standard system paths in a CLT-only environment, so their rpaths must be injected.

SWIFT_WRAPPER := $(CURDIR)/scripts/swift-wrapper.sh

CLT := /Library/Developer/CommandLineTools
FRAMEWORKS := $(CLT)/Library/Developer/Frameworks
INTEROP_LIB := $(CLT)/Library/Developer/usr/lib
PLUGINS := $(CLT)/usr/lib/swift/host/plugins/testing

BUILD_FLAGS := \
  -Xswiftc -F -Xswiftc $(FRAMEWORKS) \
  -Xswiftc -plugin-path -Xswiftc $(PLUGINS) \
  -Xlinker -rpath -Xlinker $(FRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(INTEROP_LIB)

.PHONY: build release test clean

build:
	chmod +x $(SWIFT_WRAPPER)
	SWIFT_EXEC=$(SWIFT_WRAPPER) swift build

release:
	chmod +x $(SWIFT_WRAPPER)
	SWIFT_EXEC=$(SWIFT_WRAPPER) swift build -c release

test:
	chmod +x $(SWIFT_WRAPPER)
	SWIFT_EXEC=$(SWIFT_WRAPPER) swift test $(BUILD_FLAGS)

clean:
	swift package clean
