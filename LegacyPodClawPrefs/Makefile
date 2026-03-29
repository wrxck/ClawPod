include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LegacyPodClawPrefs
LegacyPodClawPrefs_FILES = LegacyPodClawPrefsRootListController.m
LegacyPodClawPrefs_INSTALL_PATH = /Library/PreferenceBundles
LegacyPodClawPrefs_FRAMEWORKS = UIKit AudioToolbox
LegacyPodClawPrefs_PRIVATE_FRAMEWORKS = Preferences
LegacyPodClawPrefs_LIBRARIES = sqlite3
LegacyPodClawPrefs_RESOURCE_DIRS = Resources
LegacyPodClawPrefs_CFLAGS = -fno-objc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
