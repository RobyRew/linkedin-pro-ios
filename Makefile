TARGET := iphone:clang:latest:18.0
INSTALL_TARGET_PROCESSES = LinkedIn
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LinkedInPro

# Build-time codegen: write Sources/LinkedInPro/Generated/RepoSlug.swift with the
# repo slug / branch / build stamp / commit so the running tweak can report the
# exact build it came from (read as GeneratedConfig.* in Swift).
REPO_SLUG ?= $(shell git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$$|\1|')
REPO_SLUG_FINAL := $(if $(REPO_SLUG),$(REPO_SLUG),RobyRew/linkedin-pro-ios)
BRANCH_NAME ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
BRANCH_NAME_FINAL := $(if $(BRANCH_NAME),$(BRANCH_NAME),main)
LPRO_BUILD_STAMP ?= $(shell date +%Y%m%d-%H%M%S)
LPRO_BUILD_NUMBER ?= $(shell cat Outputs/.build-number 2>/dev/null || echo 0)
REPO_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

$(shell mkdir -p Sources/LinkedInPro/Generated)
$(shell printf 'enum GeneratedConfig {\n    static let repoSlug = "%s"\n    static let branchName = "%s"\n    static let buildStamp = "%s"\n    static let buildNumber = "%s"\n    static let commit = "%s"\n}\n' "$(REPO_SLUG_FINAL)" "$(BRANCH_NAME_FINAL)" "$(LPRO_BUILD_STAMP)" "$(LPRO_BUILD_NUMBER)" "$(REPO_COMMIT)" > Sources/LinkedInPro/Generated/RepoSlug.swift)

# Swift hooks live in Sources/LinkedInPro (Orion processes *.x.swift). The C
# target holds the Orion bootstrap (Tweak.m -> orion_init) and, once wired, the
# striker introspection console pulled in as a submodule under Submodules/.
# Swift = this tweak's hooks + the shared helpers from tweak-kit (consumed as a
# submodule, not copied). C = the Orion bootstrap + the striker console (from the
# striker submodule), with its header on the include path.
LinkedInPro_FILES = $(shell find Sources/LinkedInPro -name '*.swift') \
                    $(shell find Submodules/tweak-kit/swift -name '*.swift') \
                    $(shell find Sources/LinkedInProC \( -name '*.m' -o -name '*.mm' -o -name '*.cpp' \)) \
                    Submodules/striker/src/striker.m
LinkedInPro_SWIFTFLAGS = -ISources/LinkedInProC/include -ISubmodules/striker/src -Osize
LinkedInPro_CFLAGS = -fobjc-arc -ISources/LinkedInProC/include -ISubmodules/striker/src -Os
LinkedInPro_FRAMEWORKS = UIKit

# RootHide resolves jailbreak paths through libroothide at runtime; rootless
# builds use libroot. Sideload needs neither (handled by zxPluginsInject,
# LC-injected during IPA packaging).
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
LinkedInPro_SWIFTFLAGS += -D ROOTHIDE
LinkedInPro_LDFLAGS += -lroothide -Xlinker -rpath -Xlinker @loader_path/.jbroot/Library/Frameworks
else
LinkedInPro_LDFLAGS += -lroot
endif

include $(THEOS_MAKE_PATH)/tweak.mk
