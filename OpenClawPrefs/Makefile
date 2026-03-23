include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenClawPrefs
OpenClawPrefs_FILES = OpenClawPrefsRootListController.m
OpenClawPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenClawPrefs_FRAMEWORKS = UIKit AudioToolbox
OpenClawPrefs_PRIVATE_FRAMEWORKS = Preferences
OpenClawPrefs_LIBRARIES = sqlite3
OpenClawPrefs_RESOURCE_DIRS = Resources
OpenClawPrefs_CFLAGS = -fno-objc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
