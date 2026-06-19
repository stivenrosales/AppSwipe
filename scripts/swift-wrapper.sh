#!/bin/zsh
# swift-wrapper.sh
#
# Workaround for macOS 26 Tahoe CLT bug:
# libPackageDescription.dylib exports Package.__allocating_init with SwiftLanguageMode
# but the .swiftinterface declares it with the SwiftVersion typealias, causing the
# compiler to generate a call to a missing symbol.
#
# Usage (replace 'swift' with this script):
#   SWIFT_EXEC=/path/to/swift-wrapper.sh swift build
#   SWIFT_EXEC=/path/to/swift-wrapper.sh swift test <flags>
#
# For swift test you also need Testing framework flags — use Makefile targets instead.

REAL_SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc

# The symbol the compiler generates (SwiftVersion typealias — no longer in dylib)
MISSING='_$s18PackageDescription0A0C4name19defaultLocalization9platforms9pkgConfig9providers8products12dependencies7targets21swiftLanguageVersions01cN8Standard03cxxnP0ACSS_AA0N3TagVSgSayAA17SupportedPlatformVGSgSSSgSayAA06SystemA8ProviderOGSgSayAA7ProductCGSayAC10DependencyCGSayAA6TargetCGSayAA12SwiftVersionOGSgAA09CLanguageP0OSgAA011CXXLanguageP0OSgtcfC'

# The symbol actually exported by the dylib (SwiftLanguageMode — same ABI)
EXISTING='_$s18PackageDescription0A0C4name19defaultLocalization9platforms9pkgConfig9providers8products12dependencies7targets21swiftLanguageVersions01cN8Standard03cxxnP0ACSS_AA0N3TagVSgSayAA17SupportedPlatformVGSgSSSgSayAA06SystemA8ProviderOGSgSayAA7ProductCGSayAC10DependencyCGSayAA6TargetCGSayAA05SwiftN4ModeOGSgAA09CLanguageP0OSgAA011CXXLanguageP0OSgtcfC'

if [[ " $* " == *" -package-description-version "* ]]; then
    exec "$REAL_SWIFTC" \
        -Xlinker -alias -Xlinker "$EXISTING" -Xlinker "$MISSING" \
        "$@"
else
    exec "$REAL_SWIFTC" "$@"
fi
