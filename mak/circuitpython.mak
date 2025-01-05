#
# provide a default target
#
all :: upload

#
# make the targets and settings easy to view
#
help ::
	@echo "Environment Setup:"
	@echo
	@echo "  pip3 install esptool"
	@echo "  pip3 install adafruit-ampy"
	@echo

#
# - consider changing /usr/lib/python3.6/site-packages/ampy/files.py...
#   BUFFER_SIZE = 512
#

help ::
	@echo "Build Targets:"
	@echo
	@echo "  make ... (TODO)"
	@echo

help ::
	@echo "Build Settings:"
	@echo
	@echo "  PLATFORM = $(PLATFORM)"
	@echo
	@echo "  FIRMWARE_TARGET = $(FIRMWARE_TARGET)"
	@echo "  FIRMWARE_LOCALE = $(FIRMWARE_LOCALE)"
	@echo "  FIRMWARE_VERSION = $(FIRMWARE_VERSION)"
	@echo "  FIRMWARE = $(FIRMWARE)"
	@echo
	@echo "  BUNDLE_VERSION = $(BUNDLE_VERSION)"
	@echo "  BUNDLE_BUILD = $(BUNDLE_BUILD)"
	@echo "  BUNDLE = $(BUNDLE)"
	@echo
	@echo "  USB_TTY = $(USB_TTY)"
	@echo "  USB_BAUD = $(USB_BAUD)"
	@echo
	@echo "  REPL_SCREEN = $(REPL_SCREEN)"
	@echo "  REPL_BAUD = $(REPL_BAUD)"

#
# set helpful global values and command aliases
#
REPL_SCREEN ?= REPL
USB_TTY ?= /dev/ttyUSB0
USB_BAUD ?= 921600
REPL_BAUD = 115200

WGET ?= wget --no-check-certificate
ESPTOOL ?= esptool.py --chip esp32 --baud $(USB_BAUD) --port $(USB_TTY)
AMPY ?= ampy --port $(USB_TTY)

CACHE ?= $(PWD)/.cache
STAGING ?= $(PWD)/.staging
UPLOAD ?= $(PWD)/.upload

#
# set the platform name
#
PLATFORM ?= adafruit-circuitpython

#
# identify the platform firmware to use
#
FIRMWARE_TARGET ?= doit_esp32_devkit_v1
FIRMWARE_LOCALE ?= en_US
FIRMWARE_VERSION ?= 9.2.1
FIRMWARE ?= $(PLATFORM)-$(FIRMWARE_TARGET)-$(FIRMWARE_LOCALE)-$(FIRMWARE_VERSION).bin

#
# identify the module bundle
#
BUNDLE_VERSION ?= 9.x
BUNDLE_BUILD ?= 20241128
BUNDLE ?= $(PLATFORM)-bundle-$(BUNDLE_VERSION)-mpy-$(BUNDLE_BUILD)

#
# erase the current board firmware
#
erase :: unscreen
	$(ESPTOOL) erase_flash

#
# maintain a caching directory
#
cache ::
	mkdir -p $(CACHE)

clean ::
	rm -rf $(CACHE)

#
# ensure the cache is ready for the firmware
#
firmware :: cache

#
# get a copy of the board firmware
#
$(CACHE)/$(FIRMWARE) :
	$(WGET) \
		--output-document $(CACHE)/$(FIRMWARE) \
		https://downloads.circuitpython.org/bin/$(FIRMWARE_TARGET)/$(FIRMWARE_LOCALE)/$(FIRMWARE)

firmware :: $(CACHE)/$(FIRMWARE) 

#
# flash new firmware to the board
#
flash :: unscreen firmware erase
	$(ESPTOOL) write_flash -z 0x0 $(CACHE)/$(FIRMWARE)

#
# a baseline load has new firmware and nothing else
#
baseline :: erase flash

#
# ensure the cache is ready for the modules
#
modules :: cache

#
# get a copy of the module bundle
#
$(CACHE)/$(BUNDLE).zip :
	$(WGET) \
		--output-document $(CACHE)/$(BUNDLE).zip \
		https://github.com/adafruit/Adafruit_CircuitPython_Bundle/releases/download/$(BUNDLE_BUILD)/$(BUNDLE).zip

$(CACHE)/$(BUNDLE) : $(CACHE)/$(BUNDLE).zip
	cd $(CACHE) && unzip $(BUNDLE)
	cd $(CACHE) && find $(BUNDLE) -exec touch {} \;

#
# add the bundle to modules
#
modules :: $(CACHE)/$(BUNDLE) 

#
# remove any prior screen sessions that would interfere with serial
#
unscreen ::
	@ screen -list | grep REPL | awk '{print $$1}' | xargs -I % screen -S % -X quit

#
# use a screen session to interact with the REPL
#
repl :: unscreen
	rm -f repl.log
	screen -S REPL -L -Logfile repl.log /dev/ttyUSB0 $(REPL_BAUD)
	@ true || screen -S REPL -X quit 2>&1 >> /dev/null

clean ::
	rm -rf repl.log

#
# list the files on the board
#
list :: unscreen
	-$(AMPY) ls --recursive --long_format

#
# reset the board
#
reset :: unscreen
	$(AMPY) reset

#
# maintain a disaposable staging area
#
staging ::
	mkdir -p $(STAGING)
	mkdir -p $(STAGING)/lib

clean ::
	rm -rf $(STAGING)

#
# get modules for staging
#
staging :: modules

#
# copy the source files into staging
#
staging ::
	cp -rfp source/* $(STAGING)

#
# upload the staging area to the board
#
upload :: unscreen staging
	-cd $(STAGING) && \
		find . -type f -newer $(UPLOAD) | \
		xargs -r -n 1 dirname | \
		sort -u | \
		sed -e '/^\.$$/d' | \
		xargs -r -n 1 $(AMPY) mkdir >> /dev/null
	-cd $(STAGING) && \
		find -type f -newer $(UPLOAD) | \
		xargs -r -n 1 $(AMPY) rm >> /dev/null
	cd $(STAGING) && \
		find -type f -newer $(UPLOAD) -exec $(AMPY) put {} {} \;
	touch $(UPLOAD)

# cd .staging && find -mindepth 1 -maxdepth 1 -type f | xargs -n 1 $(AMPY) put

clean ::
	rm -rf $(UPLOAD)
	touch -t '01010000' $(UPLOAD)

zxcv ::
	touch -t '01010000' $(UPLOAD)

#
# download and reload everything
#
reload :: clean baseline upload

#
# upload and list the lastest staged items
#
all :: upload list

#
# run the latest staged items
#
debug :: all
	$(AMPY) run source/code.py

