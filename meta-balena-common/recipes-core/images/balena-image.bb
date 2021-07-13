SUMMARY = "Resin image"
IMAGE_LINGUAS = " "
LICENSE = "Apache-2.0"

REQUIRED_DISTRO_FEATURES += " systemd"

BALENA_FLAG_FILE = "${BALENA_IMAGE_FLAG_FILE}"

#
# The default root filesystem partition size is set in such a way that the
# entire space taken by resinOS would not exceed 700 MiB. This  can be
# overwritten by board specific layers.
#
IMAGE_ROOTFS_SIZE = "${@balena_rootfs_size(d)}"
IMAGE_OVERHEAD_FACTOR = "1.0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
IMAGE_ROOTFS_MAXSIZE = "${IMAGE_ROOTFS_SIZE}"


inherit core-image image-balena features_check

SPLASH += "plymouth-balena-theme"

IMAGE_FEATURES_append = " \
    ${@bb.utils.contains('DISTRO_FEATURES', 'development-image', 'debug-tweaks', '', d)} \
    splash \
    ssh-server-openssh \
    read-only-rootfs \
    "

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    packagegroup-resin-debugtools \
    packagegroup-balena-connectivity \
    packagegroup-resin \
    "

generate_rootfs_fingerprints () {
    # Generate fingerprints file for root filesystem
    # We exclude some entries that are bind mounted to state partition
    # and modified at runtime.
    find ${IMAGE_ROOTFS} -xdev -type f \
        -not -name ${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT} \
        -not -name hostname \
        -not -name machine-id \
        -not -name .rnd \
        -exec md5sum {} \; | sed "s#${IMAGE_ROOTFS}##g" | \
        sort -k2 > ${IMAGE_ROOTFS}/${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT}
}

generate_hostos_version () {
    echo "${HOSTOS_VERSION}" > ${DEPLOY_DIR_IMAGE}/VERSION_HOSTOS
}

DEPENDS += "jq-native"

IMAGE_PREPROCESS_COMMAND_append = " generate_rootfs_fingerprints ; "
IMAGE_POSTPROCESS_COMMAND += " generate_hostos_version ; "

BALENA_BOOT_PARTITION_FILES_append = " \
    balena-logo.png:/splash/balena-logo.png \
    os-release:/os-release \
"

# add the generated <machine-name>.json to the resin-boot partition, renamed as device-type.json
BALENA_BOOT_PARTITION_FILES_append = " ${BALENA_COREBASE}/../../../${MACHINE}.json:/device-type.json"

# example NetworkManager config file
BALENA_BOOT_PARTITION_FILES_append = " \
    system-connections/balena-sample.ignore:/system-connections/balena-sample.ignore \
    system-connections/README.ignore:/system-connections/README.ignore \
"

BALENA_BOOT_PARTITION_FILES_append = "${@ ' extra_uEnv.txt:/extra_uEnv.txt ' if d.getVar('UBOOT_MACHINE') else ''}"

# Resin image flag file
BALENA_BOOT_PARTITION_FILES_append = " ${BALENA_IMAGE_FLAG_FILE}:/${BALENA_IMAGE_FLAG_FILE}"

addtask image_size_check after do_image_balenaos_img before do_image_complete
