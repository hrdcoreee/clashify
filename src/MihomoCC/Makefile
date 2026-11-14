TARGET := iphone:clang:14.5:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MihomoCC
MihomoCC_BUNDLE_EXTENSION = bundle
MihomoCC_FILES = MihomoCCModule.m
MihomoCC_CFLAGS = -fobjc-arc
MihomoCC_FRAMEWORKS = UIKit Foundation
MihomoCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit SpringBoardServices
MihomoCC_INSTALL_PATH = /Library/ControlCenter/Bundles/

include $(THEOS_MAKE_PATH)/bundle.mk
