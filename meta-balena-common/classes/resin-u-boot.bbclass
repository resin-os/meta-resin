FILESEXTRAPATHS_append := ":${RESIN_COREBASE}/recipes-bsp/u-boot/patches"

INTEGRATION_KCONFIG_PATCH = "file://resin-specific-env-integration-kconfig.patch"
INTEGRATION_NON_KCONFIG_PATCH = "file://resin-specific-env-integration-non-kconfig.patch"

# Machine independent patches
SRC_URI_append = " \
    file://env_resin.h \
    ${@bb.utils.contains('UBOOT_KCONFIG_SUPPORT', '1', '${INTEGRATION_KCONFIG_PATCH}', '${INTEGRATION_NON_KCONFIG_PATCH}', d)} \
    "

python __anonymous() {
    # Use different integration patch based on u-boot Kconfig support
    kconfig_support = d.getVar('UBOOT_KCONFIG_SUPPORT', True)
    if not kconfig_support or (kconfig_support != '0' and kconfig_support != '1'):
        bb.error("UBOOT_KCONFIG_SUPPORT not defined or wrong value. Should be 0 or 1.")
}

# A static patch won't apply to all u-boot versions, therefore
# we edit the sources to silent the console in production builds.
do_configure_append() {
    if ${@bb.utils.contains('DISTRO_FEATURES', 'development-image', 'false', 'true', d)}; then
        if grep -qP "void puts\(const char \*s\)" ${S}/common/console.c ; then
            line=$(grep -nP "void puts\(const char \*s\)" ${S}/common/console.c | cut -f1 -d:)
            sed -i "$(expr ${line} \+ 2) i return;" ${S}/common/console.c
        else
            bbfatal "Failed to patch u-boot for silencing console in production!"
	fi;
    fi;
}


RESIN_BOOT_PART = "1"
RESIN_DEFAULT_ROOT_PART = "2"
RESIN_ENV_FILE = "resinOS_uEnv.txt"
BALENA_EXTRA_ENV_FILE = "extra_uEnv.txt"
RESIN_UBOOT_DEVICES ?= "0 1 2"
RESIN_UBOOT_DEVICE_TYPES ?= "mmc"

# OS_KERNEL_CMDLINE is a distro wide variable intended to be used in all the
# supported bootloaders
BASE_OS_CMDLINE ?= "${OS_KERNEL_CMDLINE}"
OS_BOOTCOUNT_FILE ?= "bootcount.env"
OS_BOOTCOUNT_SKIP ?= "0"
OS_BOOTCOUNT_LIMIT ?= "1"

# These options go into the device headerfile via config_resin.h
CONFIG_RESET_TO_RETRY ?= "1"
CONFIG_BOOT_RETRY_TIME ?= "${@bb.utils.contains('DISTRO_FEATURES', 'development-image', '-1', '15', d)}"

CONFIG_CMD_FS_UUID = "1"

UBOOT_VARS = "RESIN_UBOOT_DEVICES \
              RESIN_UBOOT_DEVICE_TYPES \
              RESIN_BOOT_PART RESIN_DEFAULT_ROOT_PART \
              RESIN_IMAGE_FLAG_FILE \
              RESIN_FLASHER_FLAG_FILE \
              RESIN_ENV_FILE \
              BALENA_EXTRA_ENV_FILE \
              BASE_OS_CMDLINE \
              OS_BOOTCOUNT_FILE \
              OS_BOOTCOUNT_SKIP \
              OS_BOOTCOUNT_LIMIT \
              CONFIG_RESET_TO_RETRY \
              CONFIG_BOOT_RETRY_TIME \
              CONFIG_CMD_IMPORTENV \
              CONFIG_CMD_FS_UUID "

python do_generate_resin_uboot_configuration () {
    vars = d.getVar('UBOOT_VARS').split()
    with open(os.path.join(d.getVar('S'), 'include', 'config_resin.h'), 'w') as f:
        for v in vars:
            f.write("#define %s %s\n" % (v, d.getVar(v)))

    src = bb.utils.which(d.getVar('FILESPATH'), 'env_resin.h')
    if not src:
        raise Exception('env_resin.h not found')
    dst = os.path.join(d.getVar('S'), 'include', 'env_resin.h')
    bb.utils.copyfile(src, dst)
}
addtask do_generate_resin_uboot_configuration after do_patch before do_configure

# Regenerate env_resin.h if any of these variables change.
do_generate_resin_uboot_configuration[vardeps] += "${UBOOT_VARS}"

# u-boot has config options in two places. In the devices config header
# and once via the devices defconfig file. We'd like to be able to
# inject config options in both places. We include config_resin in
# config_default to be able to inject config options that aren't
# changeable via Kconfig and config fragments.
do_inject_config_resin () {
    sed -i '/^#endif.*/i #include <config_resin.h>' ${S}/include/config_defaults.h
}

do_deploy_append() {
    touch ${DEPLOYDIR}/extra_uEnv.txt
}

addtask do_inject_config_resin after do_configure before do_compile
do_inject_config_resin[vardeps] += "${UBOOT_VARS}"
