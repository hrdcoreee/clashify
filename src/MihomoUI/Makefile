TARGET := iphone:clang:14.5:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MihomoUI
MihomoUI_FILES = main.m AppDelegate.m RootViewController.m
MihomoUI_CFLAGS = -fobjc-arc
MihomoUI_FRAMEWORKS = UIKit WebKit Foundation CoreGraphics
MihomoUI_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
