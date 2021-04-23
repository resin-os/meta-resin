inherit image_types balena-engine-rootless

#
# Create a raw image that can by written onto a storage device using dd/etcher.
#
# BALENA_IMAGE_BOOTLOADER        - bootloader
# BALENA_BOOT_PARTITION_FILES    - list of items describing files to be deployed
#                                 on boot partition
#                               - items need to be in the 'src:dst' format
#                               - src needs to be relative to DEPLOY_DIR_IMAGE
#                               - dst needs to be an absolute path
#                               - if dst is ommited ('src:' format used),
#                                 absolute path of src will be used as dst
# BALENA_ROOT_FSTYPE             - rootfs image type to be used for integrating
#                                 in the final raw image
# BALENA_BOOT_SIZE               - size of boot partition in KiB
# BALENA_RAW_IMG_COMPRESSION     - define this to compress the final raw image
#                                 with gzip, xz or bzip2
# PARTITION_TABLE_TYPE          - defines partition table type to use: gpt or
#                                 msdos. Defaults to msdos
# DEVICE_SPECIFIC_SPACE         - total amount of extra space that a device needs
#                                 for its configuration
#
#
#
# Partition table:
#
#   +-------------------+
#   |                   |  ^
#   | Reserved          |  |BALENA_IMAGE_ALIGNMENT
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Boot partition    |  |BALENA_BOOT_SIZE
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Root partition A  |  |BALENA_ROOTA_SIZE
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Root partition B  |  |BALENA_ROOTB_SIZE
#   |                   |  v
#   +-------------------+
#   |-------------------|
#   ||                 ||  ^
#   || Reserved        ||  |BALENA_IMAGE_ALIGNMENT
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || State partition ||  |BALENA_STATE_SIZE
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || Reserved        ||  |BALENA_IMAGE_ALIGNMENT
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || Data partition  ||  |BALENA_DATA_SIZE
#   ||                 ||  v
#   |-------------------|
#   +-------------------+
#

BALENA_ROOT_FSTYPE ?= "hostapp-ext4"
PARTITION_TABLE_TYPE ?= "msdos"

python() {
    # Check if we are running on a poky version which deploys to IMGDEPLOYDIR
    # instead of DEPLOY_DIR_IMAGE (poky morty introduced this change)
    if d.getVar('IMGDEPLOYDIR', True):
        d.setVar('BALENA_ROOT_FS', '${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.${BALENA_ROOT_FSTYPE}')
        d.setVar('BALENA_RAW_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.balenaos-img')
        d.setVar('BALENA_DOCKER_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.docker')
        d.setVar('BALENA_HOSTAPP_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.${BALENA_ROOT_FSTYPE}')
    else:
        d.setVar('BALENA_ROOT_FS', '${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.${BALENA_ROOT_FSTYPE}')
        d.setVar('BALENA_RAW_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.balenaos-img')
        d.setVar('BALENA_DOCKER_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docker')
        d.setVar('BALENA_HOSTAPP_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.${BALENA_ROOT_FSTYPE}')

    d.setVar('BALENA_IMAGE_BOOTLOADER_DEPLOY_TASK', ' '.join(bootloader + ':do_populate_sysroot' for bootloader in d.getVar("BALENA_IMAGE_BOOTLOADER", True).split()))
}


BALENA_BOOT_FS_LABEL ?= "resin-boot"
BALENA_ROOTA_FS_LABEL ?= "resin-rootA"
BALENA_ROOTB_FS_LABEL ?= "resin-rootB"
BALENA_STATE_FS_LABEL ?= "resin-state"
BALENA_DATA_FS_LABEL ?= "resin-data"

# By default boot partition is a fat16
BALENA_BOOT_FAT32 ?= "0"

# Sizes in KiB
BALENA_BOOT_SIZE ?= "40960"
BALENA_ROOTB_SIZE ?= ""
BALENA_STATE_SIZE ?= "20480"
BALENA_IMAGE_ALIGNMENT ?= "4096"
IMAGE_ROOTFS_ALIGNMENT = "${BALENA_IMAGE_ALIGNMENT}"
DEVICE_SPECIFIC_SPACE ?= "${BALENA_IMAGE_ALIGNMENT}"

BALENA_BOOT_WORKDIR ?= "${WORKDIR}/${BALENA_BOOT_FS_LABEL}"

BALENA_BOOT_FINGERPRINT_PATH ?= "${WORKDIR}/${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT}"
BALENA_IMAGE_BOOTLOADER ?= "virtual/bootloader"
BALENA_RAW_IMG_COMPRESSION ?= ""
BALENA_DATA_FS ?= "${DEPLOY_DIR}/images/${MACHINE}/${BALENA_DATA_FS_LABEL}.img"
BALENA_BOOT_FS = "${WORKDIR}/${BALENA_BOOT_FS_LABEL}.img"
BALENA_ROOTB_FS = "${WORKDIR}/${BALENA_ROOTB_FS_LABEL}.img"
BALENA_STATE_FS ?= "${WORKDIR}/${BALENA_STATE_FS_LABEL}.img"

# balenaos-img depends on the rootfs image
IMAGE_TYPEDEP_balenaos-img = "${BALENA_ROOT_FSTYPE}"
do_image_balenaos_img[depends] = " \
    coreutils-native:do_populate_sysroot \
    docker-disk:do_deploy \
    dosfstools-native:do_populate_sysroot \
    e2fsprogs-native:do_populate_sysroot \
    mtools-native:do_populate_sysroot \
    parted-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    ${BALENA_IMAGE_BOOTLOADER_DEPLOY_TASK} \
    "

do_image_balenaos_img[depends] += "${@ ' virtual/bootloader:do_deploy ' if d.getVar('UBOOT_CONFIG') else ''}"

device_specific_configuration() {
    echo "No device specific configuration"
}

IMAGE_CMD_balenaos-img () {
    #
    # Partition size computation (aligned to BALENA_IMAGE_ALIGNMENT)
    #

    # resin-boot
    BALENA_BOOT_SIZE_ALIGNED=$(expr ${BALENA_BOOT_SIZE} \+ ${BALENA_IMAGE_ALIGNMENT} - 1)
    BALENA_BOOT_SIZE_ALIGNED=$(expr ${BALENA_BOOT_SIZE_ALIGNED} \- ${BALENA_BOOT_SIZE_ALIGNED} \% ${BALENA_IMAGE_ALIGNMENT})

    # resin-rootA
    BALENA_ROOTA_SIZE=$(du -Lbks ${BALENA_ROOT_FS} | awk '{print $1}')
    BALENA_ROOTA_SIZE_ALIGNED=$(expr ${BALENA_ROOTA_SIZE} \+ ${BALENA_IMAGE_ALIGNMENT} \- 1)
    BALENA_ROOTA_SIZE_ALIGNED=$(expr ${BALENA_ROOTA_SIZE_ALIGNED} \- ${BALENA_ROOTA_SIZE_ALIGNED} \% ${BALENA_IMAGE_ALIGNMENT})

    # resin-rootB
    if [ -n "${BALENA_ROOTB_SIZE}" ]; then
        BALENA_ROOTB_SIZE_ALIGNED=$(expr ${BALENA_ROOTB_SIZE} \+ ${BALENA_IMAGE_ALIGNMENT} \- 1)
        BALENA_ROOTB_SIZE_ALIGNED=$(expr ${BALENA_ROOTB_SIZE_ALIGNED} \- ${BALENA_ROOTB_SIZE_ALIGNED} \% ${BALENA_IMAGE_ALIGNMENT})
    else
        BALENA_ROOTB_SIZE_ALIGNED=${BALENA_ROOTA_SIZE_ALIGNED}
    fi

    # resin-state
    if [ -n "${BALENA_STATE_FS}" ]; then
        BALENA_STATE_SIZE_ALIGNED=$(expr ${BALENA_STATE_SIZE} \+ ${BALENA_IMAGE_ALIGNMENT} \- 1)
        BALENA_STATE_SIZE_ALIGNED=$(expr ${BALENA_STATE_SIZE_ALIGNED} \- ${BALENA_STATE_SIZE_ALIGNED} \% ${BALENA_IMAGE_ALIGNMENT})
    else
        BALENA_STATE_SIZE_ALIGNED=${BALENA_IMAGE_ALIGNMENT}
    fi

    # resin-data
    if [ -n "${BALENA_DATA_FS}" ]; then
        BALENA_DATA_SIZE=`du -bks ${BALENA_DATA_FS} | awk '{print $1}'`
        BALENA_DATA_SIZE_ALIGNED=$(expr ${BALENA_DATA_SIZE} \+ ${BALENA_IMAGE_ALIGNMENT} \- 1)
        BALENA_DATA_SIZE_ALIGNED=$(expr ${BALENA_DATA_SIZE_ALIGNED} \- ${BALENA_DATA_SIZE_ALIGNED} \% ${BALENA_IMAGE_ALIGNMENT})
    else
        BALENA_DATA_SIZE_ALIGNED=${BALENA_IMAGE_ALIGNMENT}
    fi

    if [ $(expr ${DEVICE_SPECIFIC_SPACE} % ${BALENA_IMAGE_ALIGNMENT}) -ne 0  ]; then
        bbfatal "The space reserved for your specific device is not aligned to ${BALENA_IMAGE_ALIGNMENT}."
    fi

    BALENA_RAW_IMG_SIZE=$(expr \
        ${DEVICE_SPECIFIC_SPACE} \+ \
        ${BALENA_IMAGE_ALIGNMENT} \+ \
        ${BALENA_BOOT_SIZE_ALIGNED} \+ \
        ${BALENA_ROOTA_SIZE_ALIGNED} \+ \
        ${BALENA_ROOTB_SIZE_ALIGNED} \+ \
        ${BALENA_IMAGE_ALIGNMENT} \+ \
        ${BALENA_STATE_SIZE_ALIGNED} \+ \
        ${BALENA_IMAGE_ALIGNMENT} \+ \
        ${BALENA_DATA_SIZE_ALIGNED} \
    )
    echo "Creating raw image as it follow:"
    echo "  Boot partition ${BALENA_BOOT_SIZE_ALIGNED} KiB [$(expr ${BALENA_BOOT_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Root A partition ${BALENA_ROOTA_SIZE_ALIGNED} KiB [$(expr ${BALENA_ROOTA_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Root B partition ${BALENA_ROOTA_SIZE_ALIGNED} KiB [$(expr ${BALENA_ROOTB_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  State partition ${BALENA_STATE_SIZE_ALIGNED} KiB [$(expr ${BALENA_STATE_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Data partition ${BALENA_DATA_SIZE_ALIGNED} KiB [$(expr ${BALENA_DATA_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "---"
    echo "Total raw image size ${BALENA_RAW_IMG_SIZE} KiB [$(expr ${BALENA_RAW_IMG_SIZE} \/ 1024) MiB]"

    #
    # Generate the raw image with partition table
    #

    dd if=/dev/zero of=${BALENA_RAW_IMG} bs=1024 count=0 seek=${BALENA_RAW_IMG_SIZE}

    if [ "${PARTITION_TABLE_TYPE}" != "msdos" ] && [ "${PARTITION_TABLE_TYPE}" != "gpt" ]; then
        bbfatal "Unrecognized partition table: ${PARTITION_TABLE_TYPE}"
    fi

    parted ${BALENA_RAW_IMG} mklabel ${PARTITION_TABLE_TYPE}

    device_specific_configuration

    # resin-boot
    #
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        if [ "${BALENA_BOOT_FAT32}" = "1" ]; then
            OPTS="primary fat32"
        else
            OPTS="primary fat16"
        fi
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-boot"
    fi
    START=${DEVICE_SPECIFIC_SPACE}
    END=$(expr ${START} \+ ${BALENA_BOOT_SIZE_ALIGNED})
    parted -s ${BALENA_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}
    BALENA_BOOT_PN=$(parted -s ${BALENA_RAW_IMG} print | tail -n 2 | tr '\n' ' ' | awk '{print $1}')
    parted -s ${BALENA_RAW_IMG} set ${BALENA_BOOT_PN} boot on

    # resin-rootA
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="primary"
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-rootA"
    fi
    START=${END}
    END=$(expr ${START} \+ ${BALENA_ROOTA_SIZE_ALIGNED})
    parted -s ${BALENA_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}

    # resin-rootB
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="primary"
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-rootB"
    fi
    START=${END}
    END=$(expr ${START} \+ ${BALENA_ROOTB_SIZE_ALIGNED})
    parted -s ${BALENA_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}
    BALENA_ROOTB_PN=$(parted -s ${BALENA_RAW_IMG} print | tail -n 2 | tr '\n' ' ' | awk '{print $1}')

    # extended partition
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        START=${END}
        END=$(expr ${START} \+ ${BALENA_IMAGE_ALIGNMENT})
        parted -s ${BALENA_RAW_IMG} -- unit KiB mkpart extended ${START} -1s
    fi

    # resin-state
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="logical"
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-state"
    fi
    START=${END}
    END=$(expr ${START} \+ ${BALENA_STATE_SIZE_ALIGNED})
    parted -s ${BALENA_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}
    BALENA_STATE_PN=$(parted -s ${BALENA_RAW_IMG} print | tail -n 2 | tr '\n' ' ' | awk '{print $1}')

    # resin-data
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="logical"
        START=$(expr ${END} \+ ${BALENA_IMAGE_ALIGNMENT})
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-data"
        START=${END}
    fi
    parted -s ${BALENA_RAW_IMG} -- unit KiB mkpart ${OPTS} ${START} 100%

    #
    # Generate partitions
    #

    # resin-boot
    BALENA_BOOT_BLOCKS=$(LC_ALL=C parted -s ${BALENA_RAW_IMG} unit b print | grep -E "^(| )${BALENA_BOOT_PN} " | awk '{ print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -rf ${BALENA_BOOT_FS}
    OPTS="-n ${BALENA_BOOT_FS_LABEL} -S 512 -C"
    if [ "${BALENA_BOOT_FAT32}" = "1" ]; then
        OPTS="$OPTS -F 32"
    fi
    eval mkfs.vfat "$OPTS" "${BALENA_BOOT_FS}" "${BALENA_BOOT_BLOCKS}"
    if [ "$(ls -A ${BALENA_BOOT_WORKDIR})" ]; then
        mcopy -i ${BALENA_BOOT_FS} -sv ${BALENA_BOOT_WORKDIR}/* ::
    else
        bbwarn "Boot partition was detected empty."
    fi

    # resin-rootB
    BALENA_ROOTB_BLOCKS=$(LC_ALL=C parted -s ${BALENA_RAW_IMG} unit b print | grep -E "^(| )${BALENA_ROOTB_PN} " | awk '{ print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -rf ${BALENA_ROOTB_FS}
    dd if=/dev/zero of=${BALENA_ROOTB_FS} seek=${BALENA_ROOTB_BLOCKS} count=0 bs=1024
    mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 -i 8192 -F -L "${BALENA_ROOTB_FS_LABEL}" ${BALENA_ROOTB_FS}

    # resin-state
    if [ -n "${BALENA_STATE_FS}" ]; then
        BALENA_STATE_BLOCKS=$(LC_ALL=C parted -s ${BALENA_RAW_IMG} unit b print | grep -E "^(| )${BALENA_STATE_PN} " | awk '{ print substr($4, 1, length($4 -1)) / 512 /2 }')
        rm -rf ${BALENA_STATE_FS}
        dd if=/dev/zero of=${BALENA_STATE_FS} count=${BALENA_STATE_BLOCKS} bs=1024
        mkfs.ext4 -F -L "${BALENA_STATE_FS_LABEL}" ${BALENA_STATE_FS}
    fi

    # Label what is not labeled
    if case "${BALENA_ROOT_FSTYPE}" in *ext4) true;; *) false;; esac; then # can be ext4 or hostapp-ext4
        e2label ${BALENA_ROOT_FS} ${BALENA_ROOTA_FS_LABEL}
    else
        bbfatal "Rootfs labeling for type '${BALENA_ROOT_FSTYPE}' has not been implemented!"
    fi

    if [ -n "${BALENA_DATA_FS}" ]; then
        e2label ${BALENA_DATA_FS} ${BALENA_DATA_FS_LABEL}
    fi

    #
    # Burn partitions
    #
    dd if=${BALENA_BOOT_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* ${DEVICE_SPECIFIC_SPACE})
    dd if=${BALENA_ROOT_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${BALENA_BOOT_SIZE_ALIGNED}))
    dd if=${BALENA_ROOTB_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${BALENA_BOOT_SIZE_ALIGNED} \+ ${BALENA_ROOTA_SIZE_ALIGNED}))
    if [ -n "${BALENA_STATE_FS}" ]; then
        if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
            dd if=${BALENA_STATE_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${BALENA_BOOT_SIZE_ALIGNED} \+ ${BALENA_ROOTA_SIZE_ALIGNED} \+ ${BALENA_ROOTB_SIZE_ALIGNED} \+ ${BALENA_IMAGE_ALIGNMENT}))
        elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
            dd if=${BALENA_STATE_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${BALENA_BOOT_SIZE_ALIGNED} \+ ${BALENA_ROOTA_SIZE_ALIGNED} \+ ${BALENA_ROOTB_SIZE_ALIGNED}))
        fi
    fi
    if [ -n "${BALENA_DATA_FS}" ]; then
        if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
            dd if=${BALENA_DATA_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${BALENA_BOOT_SIZE_ALIGNED} \+ ${BALENA_ROOTA_SIZE_ALIGNED} \+ ${BALENA_ROOTB_SIZE_ALIGNED} \+ ${BALENA_IMAGE_ALIGNMENT} \+ ${BALENA_STATE_SIZE_ALIGNED} \+ ${BALENA_IMAGE_ALIGNMENT}))
        elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
            dd if=${BALENA_DATA_FS} of=${BALENA_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${BALENA_BOOT_SIZE_ALIGNED} \+ ${BALENA_ROOTA_SIZE_ALIGNED} \+ ${BALENA_ROOTB_SIZE_ALIGNED} \+ ${BALENA_STATE_SIZE_ALIGNED}))
        fi
    fi

    # Optionally apply compression
    case "${BALENA_RAW_IMG_COMPRESSION}" in
    "gzip")
        gzip -k9 "${BALENA_RAW_IMG}"
        ;;
    "bzip2")
        bzip2 -k9 "${BALENA_RAW_IMG}"
        ;;
    "xz")
        xz -k "${BALENA_RAW_IMG}"
        ;;
    esac
}

# Make sure we regenerate images if we modify the files that go in the boot
# partition
do_rootfs[vardeps] += "BALENA_BOOT_PARTITION_FILES"

IMAGE_CMD_docker () {
    DOCKER_IMAGE=$(${IMAGE_CMD_TAR} -cv -C ${IMAGE_ROOTFS} . | DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} import -)
    DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} save ${DOCKER_IMAGE} > ${BALENA_DOCKER_IMG}
}
IMAGE_TYPEDEP_hostapp-ext4 = "docker"

do_image_hostapp_ext4[depends] = " \
    mkfs-hostapp-native:do_populate_sysroot \
    "

IMAGE_CMD_hostapp-ext4 () {
    dd if=/dev/zero of=${BALENA_HOSTAPP_IMG} seek=$ROOTFS_SIZE count=0 bs=1024
    env ENGINE_CLIENT="${ENGINE_CLIENT}" mkfs.hostapp -t "${TMPDIR}" -s "${STAGING_DIR_NATIVE}" -i ${BALENA_DOCKER_IMG} -o ${BALENA_HOSTAPP_IMG}
}
