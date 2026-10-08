export ARCHS = armv7 arm64
export TARGET = iphone:clang:9.3:6.0

INSTALL_TARGET_PROCESSES = WALegacy

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = WALegacy

WALegacy_FILES = $(wildcard Sources/*.m)
WALegacy_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation MediaPlayer MobileCoreServices AudioToolbox
WALegacy_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/application.mk
