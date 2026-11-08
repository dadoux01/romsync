# Builds the RomSync 3DS homebrew with devkitARM (devkitPro), from the
# application template of devkitPro, without graphics or shaders.
#
#   make          romsync.3dsx (Homebrew Launcher)
#   make cia      romsync.cia (installed app; needs makerom and bannertool,
#                 which are not in devkitPro: see 3ds/README.md)
#   make clean
#
# Without devkitPro installed, use its Docker image (see 3ds/README.md):
#   podman run --rm -v "$PWD":/src -w /src/3ds docker.io/devkitpro/devkitarm make
#
# The tests of the portable core run on Linux: see tests/Makefile.

.SUFFIXES:

ifeq ($(strip $(DEVKITARM)),)
$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

TOPDIR ?= $(CURDIR)
include $(DEVKITARM)/3ds_rules

TARGET      := romsync
BUILD       := build
# app: the 3DS layer (libctru); core: the portable C core; vendor: cJSON.
SOURCES     := app core vendor/cjson
ROMFS       := romfs

APP_TITLE       := RomSync
APP_DESCRIPTION := Synchronisation des saves DS
APP_AUTHOR      := RomSync
ICON            := meta/icon.png

# Version written in the CIA (make VERSION=0.4.0 cia; "-rc1" suffixes are
# ignored).
VERSION ?= 0.0.0
VERSION_PARTS := $(subst ., ,$(firstword $(subst -, ,$(VERSION))))

ARCH    := -march=armv6k -mtune=mpcore -mfloat-abi=hard -mtp=soft
# -Wno-format-truncation: messages and paths are cut on purpose by snprintf.
# -Wstack-usage: the main thread's stack is small on the 3DS (see
# app/main.c); a function with a large frame fails the build.
CFLAGS  := -g -std=gnu99 -Wall -Wextra -Werror -Wno-format-truncation -Wstack-usage=4096 -O2 -mword-relocations \
           -ffunction-sections $(ARCH)
CFLAGS  += $(INCLUDE) -D__3DS__ -DCURL_STATICLIB
ASFLAGS := -g $(ARCH)
LDFLAGS  = -specs=3dsx.specs -g $(ARCH) -Wl,-Map,$(notdir $*.map)

# libcurl of the 3ds-curl portlib, built with mbedtls and zlib.
LIBS    := -lcurl -lmbedtls -lmbedx509 -lmbedcrypto -lz -lctru -lm
LIBDIRS := $(PORTLIBS) $(CTRULIB)

ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------
# First pass, in 3ds/: list the files, then run make again inside build/.
#---------------------------------------------------------------------------------

export OUTPUT   := $(CURDIR)/$(TARGET)
export TOPDIR   := $(CURDIR)
export VPATH    := $(foreach dir,$(SOURCES),$(CURDIR)/$(dir))
export DEPSDIR  := $(CURDIR)/$(BUILD)

CFILES          := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
export LD       := $(CC)
export OFILES   := $(CFILES:.c=.o)
export INCLUDE  := $(foreach dir,$(LIBDIRS),-I$(dir)/include) -I$(CURDIR)/$(BUILD)
export LIBPATHS := $(foreach dir,$(LIBDIRS),-L$(dir)/lib)
export APP_ICON := $(TOPDIR)/$(ICON)
export _3DSXDEPS := $(OUTPUT).smdh
export _3DSXFLAGS += --smdh=$(CURDIR)/$(TARGET).smdh --romfs=$(CURDIR)/$(ROMFS)

.PHONY: all cia clean profiles

all: profiles $(BUILD)
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile

# The conversion profiles are built into the app (romfs:/profiles); they
# can be replaced by files in sd:/3ds/romsync/profiles/.
profiles:
	@mkdir -p $(ROMFS)/profiles
	@rm -f $(ROMFS)/profiles/*.json
	@cp ../profiles/*.json $(ROMFS)/profiles/

$(BUILD):
	@mkdir -p $@

# The CIA reuses the program (romsync.elf) with a banner and an icon for the
# HOME Menu; makerom builds the romfs from the folder named in the .rsf.
cia: all
	bannertool makebanner -i meta/banner.png -a meta/banner.wav -o $(BUILD)/banner.bnr
	bannertool makesmdh -s "$(APP_TITLE)" -l "$(APP_DESCRIPTION)" -p "$(APP_AUTHOR)" \
		-i $(ICON) -o $(BUILD)/icon.icn
	makerom -f cia -o $(TARGET).cia -target t -exefslogo -elf $(TARGET).elf \
		-rsf meta/romsync.rsf -banner $(BUILD)/banner.bnr -icon $(BUILD)/icon.icn \
		-major $(word 1,$(VERSION_PARTS)) -minor $(word 2,$(VERSION_PARTS)) \
		-micro $(word 3,$(VERSION_PARTS))

clean:
	@echo clean ...
	@rm -fr $(BUILD) $(TARGET).3dsx $(TARGET).smdh $(TARGET).elf $(TARGET).cia $(ROMFS)/profiles

else
#---------------------------------------------------------------------------------
# Second pass, in build/: compile and link.
#---------------------------------------------------------------------------------

$(OUTPUT).3dsx: $(OUTPUT).elf $(_3DSXDEPS)

$(OUTPUT).elf: $(OFILES)

-include $(DEPSDIR)/*.d

endif
