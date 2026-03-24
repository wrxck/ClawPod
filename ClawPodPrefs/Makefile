include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ClawPodPrefs
ClawPodPrefs_FILES = ClawPodPrefsRootListController.m
ClawPodPrefs_INSTALL_PATH = /Library/PreferenceBundles
ClawPodPrefs_FRAMEWORKS = UIKit AudioToolbox
ClawPodPrefs_PRIVATE_FRAMEWORKS = Preferences
ClawPodPrefs_LIBRARIES = sqlite3
ClawPodPrefs_RESOURCE_DIRS = Resources
ClawPodPrefs_CFLAGS = -fno-objc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
