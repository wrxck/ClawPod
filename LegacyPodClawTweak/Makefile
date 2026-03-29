ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LegacyPodClawTweak
LegacyPodClawTweak_FILES = Tweak.xm
LegacyPodClawTweak_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security
LegacyPodClawTweak_LIBRARIES = sqlite3
LegacyPodClawTweak_CFLAGS = -Wno-deprecated-declarations -Wno-unused-variable -fno-objc-arc -I../Vendor/wolfssl -DWOLFSSL_USER_SETTINGS
LegacyPodClawTweak_OBJ_FILES += /Users/matt/openclaw-ios6/Vendor/libwolfssl.a

include $(THEOS_MAKE_PATH)/tweak.mk
