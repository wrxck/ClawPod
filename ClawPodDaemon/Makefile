include $(THEOS)/makefiles/common.mk

TOOL_NAME = clawpodd
clawpodd_FILES = main.m
clawpodd_FRAMEWORKS = Foundation CoreFoundation IOKit
clawpodd_CFLAGS = -fno-objc-arc -Wno-deprecated-declarations
clawpodd_INSTALL_PATH = /usr/bin
clawpodd_CODESIGN_FLAGS = -Sentitlements.plist
clawpodd_LDFLAGS = -ldl

include $(THEOS_MAKE_PATH)/tool.mk
