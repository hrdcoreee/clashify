ifeq ($(THEOS),)
# Standalone non-Theos fallback: compile for host or print notice
all:
	@echo "Theos not detected in environment."
	@echo "To compile MihomoCC and MihomoUI, install Theos and set THEOS=/path/to/theos"
	@echo "Or compile on device using: clang -arch arm64 src/mihomo-ctl.c -o pkg_root/usr/local/bin/mihomo-suid-helper"
else
TARGET := iphone:clang:14.5:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = mihomo-suid-helper
mihomo-suid-helper_FILES = mihomo-ctl.c
mihomo-suid-helper_CFLAGS = -fobjc-arc
mihomo-suid-helper_INSTALL_PATH = /usr/local/bin

SUBPROJECTS += MihomoUI MihomoCC

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
endif
