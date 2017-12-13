# Copyright 2009-2014, The Android-x86 Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ifneq ($(filter x86%,$(TARGET_ARCH)),)
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

ifeq ($(HOST_OS),linux)
include $(CLEAR_VARS)
LOCAL_SRC_FILES := \
		../../system/core/libdiskconfig/diskconfig.c \
		../../system/core/libdiskconfig/diskutils.c \
		../../system/core/libdiskconfig/write_lst.c \
		../../system/core/libdiskconfig/config_mbr.c
LOCAL_C_INCLUDES += system/core/libdiskconfig/include
LOCAL_MODULE := libdiskconfig_host_grub
LOCAL_MODULE_TAGS := optional
LOCAL_CFLAGS := -O2 -g -W -Wall -Werror -D_LARGEFILE64_SOURCE
include $(BUILD_HOST_STATIC_LIBRARY)
endif # HOST_OS == linux

include $(CLEAR_VARS)
LOCAL_MODULE := edit_mbr
LOCAL_C_INCLUDES += system/core/libdiskconfig/include
LOCAL_SRC_FILES := editdisklbl/editdisklbl.c
LOCAL_CFLAGS := -O2 -g -W -Wall -Werror# -D_LARGEFILE64_SOURCE
LOCAL_STATIC_LIBRARIES := libdiskconfig_host_grub libcutils liblog
edit_mbr := $(HOST_OUT_EXECUTABLES)/$(LOCAL_MODULE)
include $(BUILD_HOST_EXECUTABLE)

VER ?= $$(date +"%F")

# use squashfs for iso, unless explictly disabled
ifneq ($(USE_SQUASHFS),0)
MKSQUASHFS = $$(which mksquashfs)

define build-squashfs-target
	$(hide) $(MKSQUASHFS) $(1) $(2) -noappend -comp gzip
endef
endif

define check-density
	eval d=$$(grep ^ro.sf.lcd_density $(INSTALLED_DEFAULT_PROP_TARGET) $(INSTALLED_BUILD_PROP_TARGET) | sed 's|\(.*\)=\(.*\)|\2|'); \
	[ -z "$$d" ] || ( awk -v d=$$d ' BEGIN { \
		if (d <= 180) { \
			label="liveh"; dpi="HDPI"; \
		} else { \
			label="livem"; dpi="MDPI"; \
		} \
	} { \
		if (match($$2, label)) \
			s=5; \
		else if (match($$0, dpi)) \
			s=4; \
		else \
			s=0; \
		for (i = 0; i < s; ++i) \
			getline; \
		gsub(" DPI=[0-9]*",""); print $$0; \
	}' $(1) > $(1)_ && mv $(1)_ $(1) )
endef

initrd_dir := $(LOCAL_PATH)/initrd
initrd_bin := \
	$(initrd_dir)/init \
	$(wildcard $(initrd_dir)/*/*)
local_dir := $(LOCAL_PATH)
systemimg  := $(PRODUCT_OUT)/system.$(if $(MKSQUASHFS),sfs,img)

INITRD_RAMDISK := $(PRODUCT_OUT)/initrd.img
$(INITRD_RAMDISK): $(initrd_bin) $(systemimg) $(TARGET_INITRD_SCRIPTS) | $(ACP) $(MKBOOTFS)
	rm -rf $(TARGET_INSTALLER_OUT)
	$(ACP) -pr $(initrd_dir) $(TARGET_INSTALLER_OUT)
	$(if $(TARGET_INITRD_SCRIPTS),$(ACP) -p $(TARGET_INITRD_SCRIPTS) $(TARGET_INSTALLER_OUT)/scripts)
	ln -s /bin/ld-linux.so.2 $(TARGET_INSTALLER_OUT)/lib
	mkdir -p $(addprefix $(TARGET_INSTALLER_OUT)/,android iso mnt proc sys tmp sfs hd)
	echo "VER=$(VER)" > $(TARGET_INSTALLER_OUT)/scripts/00-ver
	$(MKBOOTFS) $(TARGET_INSTALLER_OUT) | gzip -9 > $@

OTO_INITRD_RAMDISK := $(PRODUCT_OUT)/oto_initrd.img
$(OTO_INITRD_RAMDISK): $(initrd_bin) $(systemimg) $(TARGET_INITRD_SCRIPTS) | $(ACP) $(MKBOOTFS)
	rm -rf $(TARGET_INSTALLER_OUT)
	$(ACP) -pr $(initrd_dir) $(TARGET_INSTALLER_OUT)
	$(if $(TARGET_INITRD_SCRIPTS),$(ACP) -p $(TARGET_INITRD_SCRIPTS) $(TARGET_INSTALLER_OUT)/scripts)
	ln -s /bin/ld-linux.so.2 $(TARGET_INSTALLER_OUT)/lib
	mkdir -p $(addprefix $(TARGET_INSTALLER_OUT)/,android iso mnt proc sys tmp sfs hd)
	$(ACP) -fp $(local_dir)/otoinit/init $(TARGET_INSTALLER_OUT)/
	$(MKBOOTFS) $(TARGET_INSTALLER_OUT) | gzip -9 > $@

INSTALL_RAMDISK := $(PRODUCT_OUT)/install.img
$(INSTALL_RAMDISK): $(wildcard $(LOCAL_PATH)/install/*/* $(LOCAL_PATH)/install/*/*/*/* $(LOCAL_PATH)/otoinit/install_scripts/*) $(PRODUCT_OUT)/kernel| $(MKBOOTFS)
	$(if $(TARGET_INSTALL_SCRIPTS),$(ACP) -p $(TARGET_INSTALL_SCRIPTS) $(TARGET_INSTALLER_OUT)/scripts)
	$(hide) mkdir -p $(@D)/modules/bin && ln -f `find $(@D)/obj/kernel -name atkbd.ko -o -name efivarfs.ko` $(@D)/modules/bin
	$(hide) mkdir -p $(@D)/oto/scripts && $(ACP) -fp $(local_dir)/otoinit/install_scripts/* $(@D)/oto/scripts/
	$(MKBOOTFS) $(dir $(dir $(<D))) $(@D)/modules $(@D)/oto | gzip -9 > $@

DATA_IMG := $(PRODUCT_OUT)/data.img
$(DATA_IMG): $(wildcard $(ANDROID_BUILD_TOP)/packages/apps/ExternalApp) | $(MKBOOTFS)
	$(MKBOOTFS) $^ | gzip -9 > $@

boot_dir := $(PRODUCT_OUT)/boot
$(boot_dir): $(wildcard $(LOCAL_PATH)/boot/isolinux/*) $(systemimg) $(GENERIC_X86_CONFIG_MK) | $(ACP)
	$(hide) rm -rf $@
	$(ACP) -pr $(dir $(<D)) $@

BUILT_IMG := $(addprefix $(PRODUCT_OUT)/,ramdisk.img initrd.img install.img) $(systemimg)
BUILT_IMG += $(if $(TARGET_PREBUILT_KERNEL),$(TARGET_PREBUILT_KERNEL),$(PRODUCT_OUT)/kernel)

ISO_IMAGE := $(PRODUCT_OUT)/$(BLISS_VERSION).iso
$(ISO_IMAGE): $(boot_dir) $(BUILT_IMG)
	@echo ----- Making iso image ------
	$(hide) $(call check-density,$</isolinux/isolinux.cfg)
	$(hide) sed -i "s|\(Installation CD\)\(.*\)|\1 $(VER)|; s|CMDLINE|$(BOARD_KERNEL_CMDLINE)|" $</isolinux/isolinux.cfg
	genisoimage -vJURT -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-input-charset utf-8 -V "Android-x86 LiveCD" -o $@ $^
	$(hide) isohybrid $@ || echo -e "isohybrid not found.\nInstall syslinux 4.0 or higher if you want to build a usb bootable iso."
	@echo -e "\n\n$@ is built successfully.\n\n"

# Note: requires dosfstools
EFI_IMAGE := $(PRODUCT_OUT)/$(BLISS_VERSION).img
ESP_LAYOUT := $(LOCAL_PATH)/editdisklbl/esp_layout.conf
$(EFI_IMAGE): $(wildcard $(LOCAL_PATH)/boot/efi/*/*) $(BUILT_IMG) $(ESP_LAYOUT) | $(edit_mbr)
	$(hide) sed "s|VER|$(VER)|; s|CMDLINE|$(BOARD_KERNEL_CMDLINE)|" $(<D)/grub.cfg > $(@D)/grub.cfg
	$(hide) size=0; \
	for s in `du -sk $^ | awk '{print $$1}'`; do \
		size=$$(($$size+$$s)); \
        done; \
	s=`du -sk $(<D)/../../../install/refind|awk '{print $$1}'`;size=$$(($$size+$$s)); \
	size=$$(($$(($$(($$(($$(($$size + $$(($$size / 100)))) - 1)) / 32)) + 1)) * 32)); \
	rm -f $@.fat; mkdosfs -n Android-x86 -C $@.fat $$size
	$(hide) mcopy -Qsi $@.fat $(<D)/../../../install/grub2/efi $(BUILT_IMG) ::
	$(hide) mcopy -Qsi $@.fat $(<D)/../../../install/refind ::
	$(hide) mcopy -Qoi $@.fat $(@D)/grub.cfg ::efi/boot
	$(hide) cat /dev/null > $@; $(edit_mbr) -l $(ESP_LAYOUT) -i $@ esp=$@.fat
	$(hide) rm -f $@.fat

# Note: copy from EFI_IMAGE
OTO_BUILT_IMG := $(addprefix $(PRODUCT_OUT)/,ramdisk.img install.img system.sfs)
OTO_BUILT_IMG += $(if $(TARGET_PREBUILT_KERNEL),$(TARGET_PREBUILT_KERNEL),$(PRODUCT_OUT)/kernel)
REFIND=$(PRODUCT_OUT)/efi.tar.bz2
OTO_IMAGE := $(PRODUCT_OUT)/$(BLISS_VERSION)_oto.img
ESP_LAYOUT := $(LOCAL_PATH)/editdisklbl/esp_layout.conf
$(OTO_IMAGE): $(wildcard $(LOCAL_PATH)/install/refind/*) $(OTO_INITRD_RAMDISK) $(OTO_BUILT_IMG) $(DATA_IMG) $(ESP_LAYOUT) | $(edit_mbr)
	$(hide) tar jcf $(REFIND) -C $(<D) efi
	$(hide) cp $(PRODUCT_OUT)/oto_initrd.img $(PRODUCT_OUT)/initrd.img
	$(hide) size=0; \
	for s in `du -sk $^ | awk '{print $$1}'`; do \
		size=$$(($$size+$$s)); \
        done; \
	s=`du -sk $(REFIND)|awk '{print $$1}'`;size=$$(($$size+$$s + 8096)); \
	size=$$(($$(($$(($$(($$(($$size + $$(($$size / 100)))) - 1)) / 32)) + 1)) * 32)); \
	rm -f $@.fat; mkdosfs -n OTO_INSTDSK -C $@.fat $$size
	$(hide) mcopy -Qsi $@.fat $(<D)/efi ::
	$(hide) mmd -i $@.fat ::OpenThos
	$(hide) mcopy -Qsi $@.fat $(OTO_BUILT_IMG) $(DATA_IMG) $(PRODUCT_OUT)/initrd.img $(REFIND) $(<D)/boto_linux.conf ::OpenThos/
	$(hide) cat /dev/null > $@; $(edit_mbr) -l $(ESP_LAYOUT) -i $@ esp=$@.fat
	$(hide) rm -f $@.fat $(PRODUCT_OUT)/initrd.img

VERSION_FILE=$(local_dir)/otoinit/version
UPDATE_LIST=$(local_dir)/otoinit/update.list
UPDATE=openthos
VERSION := $(shell cat $(VERSION_FILE)|awk '/OpenThos/{print $$2;}')

UPDATE_IMG:= $(addprefix $(PRODUCT_OUT)/, $(shell cat $(UPDATE_LIST)))
UPDATE_ZIP := $(PRODUCT_OUT)/$(UPDATE)_$(VERSION).zip
$(UPDATE_ZIP): $(VERSION_FILE) $(UPDATE_LIST) $(OTO_IMAGE)
	$(hide) rm -rf $@
	$(hide) zip -qj $@ $(UPDATE_IMG) $(VERSION_FILE) $(UPDATE_LIST)

.PHONY: iso_img usb_img efi_img oto_img update_zip
iso_img: $(ISO_IMAGE)
usb_img: $(ISO_IMAGE)
efi_img: $(EFI_IMAGE)
oto_img: $(OTO_IMAGE)
update_zip:$(UPDATE_ZIP)

endif
