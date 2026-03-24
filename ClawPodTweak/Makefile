ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ClawPodTweak
ClawPodTweak_FILES = Tweak.xm
ClawPodTweak_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security
ClawPodTweak_LIBRARIES = sqlite3
ClawPodTweak_CFLAGS = -Wno-deprecated-declarations -Wno-unused-variable -fno-objc-arc -I../Vendor/wolfssl -DWOLFSSL_USER_SETTINGS
ClawPodTweak_OBJ_FILES += /Users/matt/openclaw-ios6/Vendor/libwolfssl.a

include $(THEOS_MAKE_PATH)/tweak.mk
