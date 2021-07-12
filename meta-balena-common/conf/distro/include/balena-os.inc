# Poky based distro file
require conf/distro/poky.conf
include conf/distro/include/balena-os-yocto-version.inc

DISTRO = "balena-os"
DISTRO_NAME = "balenaOS"
DISTRO_VERSION = "2.83.0"
HOSTOS_VERSION = "${DISTRO_VERSION}"
python () {
    ''' Set HOSTOS_VERSION from board VERSION if available '''

    # Find board VERSION location based on poky meta layer
    bblayers = d.getVar('BBLAYERS', True).split()
    poky = [layer for layer in bblayers if layer.endswith('poky/meta')]
    if not poky:
        return
    board_version_path = os.path.join(poky[0], '../../../', 'VERSION')

    # Set HOSTOS_VERSION
    try:
        with open(board_version_path, 'r') as v:
            board_version = v.read().strip()
        d.setVar('HOSTOS_VERSION', board_version)
    except:
        return
}

MAINTAINER = "Balena <hello@balena.io>"

# Strip down unneeded features
POKY_DEFAULT_DISTRO_FEATURES_remove = "ptest"
POKY_DEFAULT_DISTRO_FEATURES_remove = "wayland"
DISTRO_FEATURES_DEFAULT_remove = "x11"

# OS development image
OS_DEVELOPMENT ?= "0"
DISTRO_FEATURES_append = " ${@bb.utils.contains('OS_DEVELOPMENT','1','osdev-image','',d)}"

# Providers
PREFERRED_PROVIDER_docker ?= "docker"
PREFERRED_PROVIDER_jpeg ?= "jpeg"
PREFERRED_PROVIDER_jpeg-native ?= "jpeg-native"

SPLASH = "plymouth"

IMAGE_CLASSES += "image_types_balena"

# Define the URL where resin exposes source or prebuilt packages
AMAZON_BALENA_SHARE = "https://s3.amazonaws.com/resin-share/build_requirements"

# have build information available on the target under /etc/build
INHERIT += "image-buildinfo resin-sanity"

# Identification file flags
BALENA_IMAGE_FLAG_FILE = "balena-image"
BALENA_FLASHER_FLAG_FILE = "balena-image-flasher"

# Kernel command line
OS_KERNEL_CMDLINE ?= "${@bb.utils.contains('OS-DEVELOPMENT','1','', 'console=null quiet splash vt.global_cursor_default=0 consoleblank=0',d)}"

# Initramfs
INITRAMFS_IMAGE = "balena-image-initramfs"
INITRAMFS_IMAGE_BUNDLE = "1"
KERNEL_INITRAMFS = "-initramfs"
INITRAMFS_TASK = ""

# resinOS defaults to ipk packages
PACKAGE_CLASSES ?= "package_ipk"

# Default the docker storage driver to aufs
BALENA_STORAGE ?= "aufs"
python () {
    docker_storage = d.getVar('DOCKER_STORAGE', True)
    if docker_storage:
        d.setVar('BALENA_STORAGE', docker_storage)
}

# Partition fingerprints files
BALENA_FINGERPRINT_EXT ?= "fingerprint"
BALENA_FINGERPRINT_FILENAME ?= "balenaos"

# Hostname is generated at runtime based on config.json
hostname_pn-base-files = ""

BAD_RECOMMENDATIONS += "shared-mime-info"

# ARM data -> instruction cache consistency bug in latest UPX
# Downgrade to avoid this bug
# https://github.com/upx/upx/issues/225
PREFERRED_VERSION_upx_arm = "3.94"
PREFERRED_VERSION_upx-native_arm = "3.94"

# let's pin linux-firmware to the version we imported from Poky zeus-22.0.1 release
PREFERRED_VERSION_linux-firmware = "20190815"

# Preferred rust version
PREFERRED_VERSION_rust-native = "1.36.0"
PREFERRED_VERSION_rust-cross-arm = "1.36.0"
PREFERRED_VERSION_rust-llvm-native = "1.36.0"
PREFERRED_VERSION_cargo-native = "1.36.0"
PREFERRED_VERSION_libstd-rs = "1.36.0"

# balena-engine go version requirement
GOVERSION = "1.12.17"
PREFERRED_PROVIDER_go-native = "go-native"
