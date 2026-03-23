# ClawPod - Theos Makefile
# Target: iPod Touch 4th gen, ARMv7, iOS 6.0+
# Full gateway + channels + providers + tools + media + plugins

INSTALL_TARGET_PROCESSES = ClawPod

ARCHS = armv7
TARGET = iphone:clang:14.5:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ClawPod

ClawPod_FILES = \
	main.m \
	Classes/AppDelegate.m \
	Classes/UI/OCRootViewController.m \
	Classes/UI/OCChatViewController.m \
	Classes/UI/OCChatCell.m \
	Classes/UI/OCSessionListViewController.m \
	Classes/UI/OCSettingsViewController.m \
	Classes/Utils/OCLogger.m \
	Classes/Services/OCConnectionService.m \
	Classes/Services/OCVoiceService.m \
	Frameworks/OCWebSocket/OCWebSocket.m \
	Frameworks/OCMemory/OCMemoryPool.m \
	Frameworks/OCStore/OCStore.m \
	Frameworks/OCGateway/OCGatewayClient.m \
	Frameworks/OCChat/OCChatSession.m \
	Frameworks/OCAgent/OCAgent.m \
	Frameworks/OCServer/OCHTTPServer.m \
	Frameworks/OCServer/OCGatewayServer.m \
	Frameworks/OCChannels/OCChannelManager.m \
	Frameworks/OCChannels/OCTelegramChannel.m \
	Frameworks/OCChannels/OCDiscordChannel.m \
	Frameworks/OCChannels/OCIRCChannel.m \
	Frameworks/OCChannels/OCSlackChannel.m \
	Frameworks/OCChannels/OCWebhookChannel.m \
	Frameworks/OCProviders/OCProviderRegistry.m \
	Frameworks/OCTools/OCExtendedTools.m \
	Frameworks/OCMedia/OCMediaPipeline.m \
	Frameworks/OCPlugin/OCPluginSDK.m \
	Frameworks/OCTools/OCSystemMCP.m \
	Frameworks/OCTools/OCGuardrails.m \
	Frameworks/OCTools/OCSkillRegistry.m \
	Frameworks/OCTools/OCNotesReminders.m \
	Frameworks/OCSystem/OCSystem.m \
	Frameworks/OCSystem/CPLauncher.m

ClawPod_CFLAGS = \
	-IFrameworks/OCWebSocket \
	-IFrameworks/OCMemory \
	-IFrameworks/OCStore \
	-IFrameworks/OCGateway \
	-IFrameworks/OCChat \
	-IFrameworks/OCAgent \
	-IFrameworks/OCServer \
	-IFrameworks/OCChannels \
	-IFrameworks/OCProviders \
	-IFrameworks/OCTools \
	-IFrameworks/OCMedia \
	-IFrameworks/OCPlugin \
	-IFrameworks/OCSystem \
	-IClasses \
	-IClasses/UI \
	-IClasses/Utils \
	-IClasses/Services \
	-fobjc-arc-exceptions \
	-Wno-deprecated-declarations \
	-Wno-unused-variable \
	-Wno-objc-method-access \
	-Wno-incompatible-pointer-types \
	-Wno-objc-protocol-property-synthesis \
	-Wno-protocol

ClawPod_OBJCFLAGS = -fno-objc-arc

ClawPod_FRAMEWORKS = UIKit Foundation Security CoreGraphics QuartzCore AudioToolbox AVFoundation SystemConfiguration CFNetwork IOKit

ClawPod_LIBRARIES = sqlite3

ClawPod_CFLAGS += -Os -ffast-math -fvisibility=hidden -fvisibility-inlines-hidden
ClawPod_LDFLAGS = -dead_strip -ldl

ClawPod_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS += ClawPodPrefs ClawPodTweak ClawPodNC ClawPodDaemon
include $(THEOS_MAKE_PATH)/aggregate.mk
