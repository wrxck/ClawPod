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
	Classes/UI/RootViewController.m \
	Classes/UI/ChatViewController.m \
	Classes/UI/ChatCell.m \
	Classes/UI/SessionListViewController.m \
	Classes/UI/SettingsViewController.m \
	Classes/Utils/Logger.m \
	Classes/Services/ConnectionService.m \
	Classes/Services/VoiceService.m \
	Frameworks/WebSocket/WebSocket.m \
	Frameworks/Memory/MemoryPool.m \
	Frameworks/Store/Store.m \
	Frameworks/Gateway/GatewayClient.m \
	Frameworks/Chat/ChatSession.m \
	Frameworks/Agent/Agent.m \
	Frameworks/Server/HTTPServer.m \
	Frameworks/Server/GatewayServer.m \
	Frameworks/Channels/ChannelManager.m \
	Frameworks/Channels/TelegramChannel.m \
	Frameworks/Channels/DiscordChannel.m \
	Frameworks/Channels/IRCChannel.m \
	Frameworks/Channels/SlackChannel.m \
	Frameworks/Channels/WebhookChannel.m \
	Frameworks/Providers/ProviderRegistry.m \
	Frameworks/Tools/ExtendedTools.m \
	Frameworks/Media/MediaPipeline.m \
	Frameworks/Plugin/PluginSDK.m \
	Frameworks/Tools/SystemMCP.m \
	Frameworks/Tools/Guardrails.m \
	Frameworks/Tools/SkillRegistry.m \
	Frameworks/Tools/NotesReminders.m \
	Frameworks/Tools/MusicDownloader.m \
	Frameworks/System/System.m \
	Frameworks/System/TLSClient.m

ClawPod_CFLAGS = \
	-IFrameworks/WebSocket \
	-IFrameworks/Memory \
	-IFrameworks/Store \
	-IFrameworks/Gateway \
	-IFrameworks/Chat \
	-IFrameworks/Agent \
	-IFrameworks/Server \
	-IFrameworks/Channels \
	-IFrameworks/Providers \
	-IFrameworks/Tools \
	-IFrameworks/Media \
	-IFrameworks/Plugin \
	-IFrameworks/System \
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
	-Wno-protocol \
	-IVendor/wolfssl \
	-DWOLFSSL_USER_SETTINGS

ClawPod_OBJCFLAGS = -fno-objc-arc

ClawPod_FRAMEWORKS = UIKit Foundation Security CoreGraphics QuartzCore AudioToolbox AVFoundation SystemConfiguration CFNetwork IOKit

ClawPod_LIBRARIES = sqlite3

ClawPod_CFLAGS += -Os -ffast-math -fvisibility=hidden -fvisibility-inlines-hidden
ClawPod_LDFLAGS = -dead_strip -ldl
ClawPod_OBJ_FILES += /Users/matt/openclaw-ios6/Vendor/libwolfssl.a

ClawPod_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS += ClawPodPrefs ClawPodTweak ClawPodNC ClawPodDaemon
include $(THEOS_MAKE_PATH)/aggregate.mk
