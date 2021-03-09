inherit image_types

#
# Create a raw image that can by written onto a storage device using dd/etcher.
#
# RESIN_IMAGE_BOOTLOADER        - bootloader
# RESIN_BOOT_PARTITION_FILES    - list of items describing files to be deployed
#                                 on boot partition
#                               - items need to be in the 'src:dst' format
#                               - src needs to be relative to DEPLOY_DIR_IMAGE
#                               - dst needs to be an absolute path
#                               - if dst is ommited ('src:' format used),
#                                 absolute path of src will be used as dst
# RESIN_ROOT_FSTYPE             - rootfs image type to be used for integrating
#                                 in the final raw image
# RESIN_BOOT_SIZE               - size of boot partition in KiB
# RESIN_RAW_IMG_COMPRESSION     - define this to compress the final raw image
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
#   | Reserved          |  |RESIN_IMAGE_ALIGNMENT
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Boot partition    |  |RESIN_BOOT_SIZE
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Root partition A  |  |RESIN_ROOTA_SIZE
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Root partition B  |  |RESIN_ROOTB_SIZE
#   |                   |  v
#   +-------------------+
#   |-------------------|
#   ||                 ||  ^
#   || Reserved        ||  |RESIN_IMAGE_ALIGNMENT
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || State partition ||  |RESIN_STATE_SIZE
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || Reserved        ||  |RESIN_IMAGE_ALIGNMENT
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || Data partition  ||  |RESIN_DATA_SIZE
#   ||                 ||  v
#   |-------------------|
#   +-------------------+
#

RESIN_ROOT_FSTYPE ?= "hostapp-${BALENA_FSTYPE}"
PARTITION_TABLE_TYPE ?= "msdos"

python() {
    # Check if we are running on a poky version which deploys to IMGDEPLOYDIR
    # instead of DEPLOY_DIR_IMAGE (poky morty introduced this change)
    if d.getVar('IMGDEPLOYDIR', True):
        d.setVar('RESIN_ROOT_FS', '${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.${RESIN_ROOT_FSTYPE}')
        d.setVar('RESIN_RAW_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.resinos-img')
        d.setVar('RESIN_DOCKER_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.docker')
        d.setVar('RESIN_HOSTAPP_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.${RESIN_ROOT_FSTYPE}')
    else:
        d.setVar('RESIN_ROOT_FS', '${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.${RESIN_ROOT_FSTYPE}')
        d.setVar('RESIN_RAW_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.resinos-img')
        d.setVar('RESIN_DOCKER_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docker')
        d.setVar('RESIN_HOSTAPP_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.${RESIN_ROOT_FSTYPE}')

    d.setVar('RESIN_IMAGE_BOOTLOADER_DEPLOY_TASK', ' '.join(bootloader + ':do_populate_sysroot' for bootloader in d.getVar("RESIN_IMAGE_BOOTLOADER", True).split()))
}


RESIN_BOOT_FS_LABEL ?= "resin-boot"
RESIN_ROOTA_FS_LABEL ?= "resin-rootA"
RESIN_ROOTB_FS_LABEL ?= "resin-rootB"
RESIN_STATE_FS_LABEL ?= "resin-state"
RESIN_DATA_FS_LABEL ?= "resin-data"

# By default boot partition is a fat16
BALENA_BOOT_FAT32 ?= "0"

# Sizes in KiB
RESIN_BOOT_SIZE ?= "40960"
RESIN_ROOTB_SIZE ?= ""
RESIN_STATE_SIZE ?= "20480"
RESIN_IMAGE_ALIGNMENT ?= "4096"
IMAGE_ROOTFS_ALIGNMENT = "${RESIN_IMAGE_ALIGNMENT}"
DEVICE_SPECIFIC_SPACE ?= "${RESIN_IMAGE_ALIGNMENT}"

RESIN_BOOT_WORKDIR ?= "${WORKDIR}/${RESIN_BOOT_FS_LABEL}"

RESIN_BOOT_FINGERPRINT_PATH ?= "${WORKDIR}/${RESIN_FINGERPRINT_FILENAME}.${RESIN_FINGERPRINT_EXT}"
RESIN_IMAGE_BOOTLOADER ?= "virtual/bootloader"
RESIN_RAW_IMG_COMPRESSION ?= ""
RESIN_DATA_FS ?= "${DEPLOY_DIR}/images/${MACHINE}/${RESIN_DATA_FS_LABEL}.img"
RESIN_BOOT_FS = "${WORKDIR}/${RESIN_BOOT_FS_LABEL}.img"
RESIN_ROOTB_FS = "${WORKDIR}/${RESIN_ROOTB_FS_LABEL}.img"
RESIN_STATE_FS ?= "${WORKDIR}/${RESIN_STATE_FS_LABEL}.img"

# resinos-img depends on the rootfs image
IMAGE_TYPEDEP_resinos-img = "${RESIN_ROOT_FSTYPE}"
do_image_resinos_img[depends] = " \
    coreutils-native:do_populate_sysroot \
    docker-disk:do_deploy \
    dosfstools-native:do_populate_sysroot \
    e2fsprogs-native:do_populate_sysroot \
    mtools-native:do_populate_sysroot \
    parted-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    ${RESIN_IMAGE_BOOTLOADER_DEPLOY_TASK} \
    "

do_image_resinos_img[depends] += "${@ ' virtual/bootloader:do_deploy ' if d.getVar('UBOOT_CONFIG') else ''}"

device_specific_configuration() {
    echo "No device specific configuration"
}

IMAGE_CMD_resinos-img () {
    #
    # Partition size computation (aligned to RESIN_IMAGE_ALIGNMENT)
    #

    # resin-boot
    RESIN_BOOT_SIZE_ALIGNED=$(expr ${RESIN_BOOT_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} - 1)
    RESIN_BOOT_SIZE_ALIGNED=$(expr ${RESIN_BOOT_SIZE_ALIGNED} \- ${RESIN_BOOT_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})

    # resin-rootA
    RESIN_ROOTA_SIZE=$(du -Lbks ${RESIN_ROOT_FS} | awk '{print $1}')
    RESIN_ROOTA_SIZE_ALIGNED=$(expr ${RESIN_ROOTA_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
    RESIN_ROOTA_SIZE_ALIGNED=$(expr ${RESIN_ROOTA_SIZE_ALIGNED} \- ${RESIN_ROOTA_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})

    # resin-rootB
    if [ -n "${RESIN_ROOTB_SIZE}" ]; then
        RESIN_ROOTB_SIZE_ALIGNED=$(expr ${RESIN_ROOTB_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
        RESIN_ROOTB_SIZE_ALIGNED=$(expr ${RESIN_ROOTB_SIZE_ALIGNED} \- ${RESIN_ROOTB_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})
    else
        RESIN_ROOTB_SIZE_ALIGNED=${RESIN_ROOTA_SIZE_ALIGNED}
    fi

    # resin-state
    if [ -n "${RESIN_STATE_FS}" ]; then
        RESIN_STATE_SIZE_ALIGNED=$(expr ${RESIN_STATE_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
        RESIN_STATE_SIZE_ALIGNED=$(expr ${RESIN_STATE_SIZE_ALIGNED} \- ${RESIN_STATE_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})
    else
        RESIN_STATE_SIZE_ALIGNED=${RESIN_IMAGE_ALIGNMENT}
    fi

    # resin-data
    if [ -n "${RESIN_DATA_FS}" ]; then
        RESIN_DATA_SIZE=`du -bks ${RESIN_DATA_FS} | awk '{print $1}'`
        RESIN_DATA_SIZE_ALIGNED=$(expr ${RESIN_DATA_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
        RESIN_DATA_SIZE_ALIGNED=$(expr ${RESIN_DATA_SIZE_ALIGNED} \- ${RESIN_DATA_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})
    else
        RESIN_DATA_SIZE_ALIGNED=${RESIN_IMAGE_ALIGNMENT}
    fi

    if [ $(expr ${DEVICE_SPECIFIC_SPACE} % ${RESIN_IMAGE_ALIGNMENT}) -ne 0  ]; then
        bbfatal "The space reserved for your specific device is not aligned to ${RESIN_IMAGE_ALIGNMENT}."
    fi

    RESIN_RAW_IMG_SIZE=$(expr \
        ${DEVICE_SPECIFIC_SPACE} \+ \
        ${RESIN_IMAGE_ALIGNMENT} \+ \
        ${RESIN_BOOT_SIZE_ALIGNED} \+ \
        ${RESIN_ROOTA_SIZE_ALIGNED} \+ \
        ${RESIN_ROOTB_SIZE_ALIGNED} \+ \
        ${RESIN_IMAGE_ALIGNMENT} \+ \
        ${RESIN_STATE_SIZE_ALIGNED} \+ \
        ${RESIN_IMAGE_ALIGNMENT} \+ \
        ${RESIN_DATA_SIZE_ALIGNED} \
    )
    echo "Creating raw image as it follow:"
    echo "  Boot partition ${RESIN_BOOT_SIZE_ALIGNED} KiB [$(expr ${RESIN_BOOT_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Root A partition ${RESIN_ROOTA_SIZE_ALIGNED} KiB [$(expr ${RESIN_ROOTA_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Root B partition ${RESIN_ROOTA_SIZE_ALIGNED} KiB [$(expr ${RESIN_ROOTB_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  State partition ${RESIN_STATE_SIZE_ALIGNED} KiB [$(expr ${RESIN_STATE_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Data partition ${RESIN_DATA_SIZE_ALIGNED} KiB [$(expr ${RESIN_DATA_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "---"
    echo "Total raw image size ${RESIN_RAW_IMG_SIZE} KiB [$(expr ${RESIN_RAW_IMG_SIZE} \/ 1024) MiB]"

    #
    # Generate the raw image with partition table
    #

    dd if=/dev/zero of=${RESIN_RAW_IMG} bs=1024 count=0 seek=${RESIN_RAW_IMG_SIZE}

    if [ "${PARTITION_TABLE_TYPE}" != "msdos" ] && [ "${PARTITION_TABLE_TYPE}" != "gpt" ]; then
        bbfatal "Unrecognized partition table: ${PARTITION_TABLE_TYPE}"
    fi

    parted ${RESIN_RAW_IMG} mklabel ${PARTITION_TABLE_TYPE}

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
    END=$(expr ${START} \+ ${RESIN_BOOT_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}
    RESIN_BOOT_PN=$(parted -s ${RESIN_RAW_IMG} print | tail -n 2 | tr '\n' ' ' | awk '{print $1}')
    parted -s ${RESIN_RAW_IMG} set ${RESIN_BOOT_PN} boot on

    # resin-rootA
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="primary"
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-rootA"
    fi
    START=${END}
    END=$(expr ${START} \+ ${RESIN_ROOTA_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}

    # resin-rootB
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="primary"
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-rootB"
    fi
    START=${END}
    END=$(expr ${START} \+ ${RESIN_ROOTB_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}
    RESIN_ROOTB_PN=$(parted -s ${RESIN_RAW_IMG} print | tail -n 2 | tr '\n' ' ' | awk '{print $1}')

    # extended partition
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        START=${END}
        END=$(expr ${START} \+ ${RESIN_IMAGE_ALIGNMENT})
        parted -s ${RESIN_RAW_IMG} -- unit KiB mkpart extended ${START} -1s
    fi

    # resin-state
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="logical"
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-state"
    fi
    START=${END}
    END=$(expr ${START} \+ ${RESIN_STATE_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart ${OPTS} ${START} ${END}
    RESIN_STATE_PN=$(parted -s ${RESIN_RAW_IMG} print | tail -n 2 | tr '\n' ' ' | awk '{print $1}')

    # resin-data
    if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
        OPTS="logical"
        START=$(expr ${END} \+ ${RESIN_IMAGE_ALIGNMENT})
    elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
        OPTS="resin-data"
        START=${END}
    fi
    parted -s ${RESIN_RAW_IMG} -- unit KiB mkpart ${OPTS} ${START} 100%

    #
    # Generate partitions
    #

    # resin-boot
    RESIN_BOOT_BLOCKS=$(LC_ALL=C parted -s ${RESIN_RAW_IMG} unit b print | grep -E "^(| )${RESIN_BOOT_PN} " | awk '{ print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -rf ${RESIN_BOOT_FS}
    OPTS="-n ${RESIN_BOOT_FS_LABEL} -S 512 -C"
    if [ "${BALENA_BOOT_FAT32}" = "1" ]; then
        OPTS="$OPTS -F 32"
    fi
    eval mkfs.vfat "$OPTS" "${RESIN_BOOT_FS}" "${RESIN_BOOT_BLOCKS}"
    if [ "$(ls -A ${RESIN_BOOT_WORKDIR})" ]; then
        mcopy -i ${RESIN_BOOT_FS} -sv ${RESIN_BOOT_WORKDIR}/* ::
    else
        bbwarn "Boot partition was detected empty."
    fi

    # resin-rootB
    RESIN_ROOTB_BLOCKS=$(LC_ALL=C parted -s ${RESIN_RAW_IMG} unit b print | grep -E "^(| )${RESIN_ROOTB_PN} " | awk '{ print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -rf ${RESIN_ROOTB_FS}
    dd if=/dev/zero of=${RESIN_ROOTB_FS} seek=${RESIN_ROOTB_BLOCKS} count=0 bs=1024
    mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 -i 8192 -F -L "${RESIN_ROOTB_FS_LABEL}" ${RESIN_ROOTB_FS}

    # resin-state
    if [ -n "${RESIN_STATE_FS}" ]; then
        RESIN_STATE_BLOCKS=$(LC_ALL=C parted -s ${RESIN_RAW_IMG} unit b print | grep -E "^(| )${RESIN_STATE_PN} " | awk '{ print substr($4, 1, length($4 -1)) / 512 /2 }')
        rm -rf ${RESIN_STATE_FS}
        dd if=/dev/zero of=${RESIN_STATE_FS} count=${RESIN_STATE_BLOCKS} bs=1024
        mkfs.ext4 -F -L "${RESIN_STATE_FS_LABEL}" ${RESIN_STATE_FS}
    fi

    # Label what is not labeled
    if [ "${RESIN_ROOT_FSTYPE}" = "hostapp-ext4" ]; then
        e2label ${RESIN_ROOT_FS} ${RESIN_ROOTA_FS_LABEL}
    elif [ "${RESIN_ROOT_FSTYPE}" = "hostapp-btrfs" ]; then
        btrfs fi label ${RESIN_ROOT_FS} ${RESIN_ROOTA_FS_LABEL}
    else
        bbfatal  "Rootfs labeling for type ${RESIN_ROOT_FSTYPE} has not been implemented!"
    fi

    if [ -n "${RESIN_DATA_FS}" ]; then
        e2label ${RESIN_DATA_FS} ${RESIN_DATA_FS_LABEL}
    fi

    #
    # Burn partitions
    #
    dd if=${RESIN_BOOT_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* ${DEVICE_SPECIFIC_SPACE})
    dd if=${RESIN_ROOT_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${RESIN_BOOT_SIZE_ALIGNED}))
    dd if=${RESIN_ROOTB_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED}))
    if [ -n "${RESIN_STATE_FS}" ]; then
        if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
            dd if=${RESIN_STATE_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED} \+ ${RESIN_ROOTB_SIZE_ALIGNED} \+ ${RESIN_IMAGE_ALIGNMENT}))
        elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
            dd if=${RESIN_STATE_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED} \+ ${RESIN_ROOTB_SIZE_ALIGNED}))
        fi
    fi
    if [ -n "${RESIN_DATA_FS}" ]; then
        if [ "${PARTITION_TABLE_TYPE}" = "msdos" ]; then
            dd if=${RESIN_DATA_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED} \+ ${RESIN_ROOTB_SIZE_ALIGNED} \+ ${RESIN_IMAGE_ALIGNMENT} \+ ${RESIN_STATE_SIZE_ALIGNED} \+ ${RESIN_IMAGE_ALIGNMENT}))
        elif [ "${PARTITION_TABLE_TYPE}" = "gpt" ]; then
            dd if=${RESIN_DATA_FS} of=${RESIN_RAW_IMG} conv=notrunc seek=1 bs=$(expr 1024 \* $(expr ${DEVICE_SPECIFIC_SPACE} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED} \+ ${RESIN_ROOTB_SIZE_ALIGNED} \+ ${RESIN_STATE_SIZE_ALIGNED}))
        fi
    fi

    # Optionally apply compression
    case "${RESIN_RAW_IMG_COMPRESSION}" in
    "gzip")
        gzip -k9 "${RESIN_RAW_IMG}"
        ;;
    "bzip2")
        bzip2 -k9 "${RESIN_RAW_IMG}"
        ;;
    "xz")
        xz -k "${RESIN_RAW_IMG}"
        ;;
    esac
}

# Make sure we regenerate images if we modify the files that go in the boot
# partition
do_rootfs[vardeps] += "RESIN_BOOT_PARTITION_FILES"

# XXX(petrosagg): This should be eventually implemented using a docker-native daemon
IMAGE_CMD_docker () {
    DOCKER_IMAGE=$(${IMAGE_CMD_TAR} -cv -C ${IMAGE_ROOTFS} . | DOCKER_API_VERSION=1.22 docker import -)
    DOCKER_API_VERSION=1.22 docker save ${DOCKER_IMAGE} > ${RESIN_DOCKER_IMG}
}

IMAGE_TYPEDEP_hostapp-ext4 = "docker"

do_image_hostapp_ext4[depends] = " \
    mkfs-hostapp-native:do_populate_sysroot \
    "

IMAGE_CMD_hostapp-ext4 () {
    dd if=/dev/zero of=${RESIN_HOSTAPP_IMG} seek=$ROOTFS_SIZE count=0 bs=1024
    mkfs.hostapp -f ext4 \
                 -t "${TMPDIR}" \
                 -s "${STAGING_DIR_NATIVE}" \
                 -i ${RESIN_DOCKER_IMG} \
                 -o ${RESIN_HOSTAPP_IMG}
}

IMAGE_TYPEDEP_hostapp-btrfs = "docker"

do_image_hostapp_btrfs[depends] = " \
    mkfs-hostapp-native:do_populate_sysroot \
    btrfs-tools-native:do_populate_sysroot \
    "

IMAGE_CMD_hostapp-btrfs () {
    dd if=/dev/zero of=${RESIN_HOSTAPP_IMG} seek=$ROOTFS_SIZE count=0 bs=1024
    mkfs.hostapp -f btrfs \
                 -t "${TMPDIR}" \
                 -s "${STAGING_DIR_NATIVE}" \
                 -i ${RESIN_DOCKER_IMG} \
                 -o ${RESIN_HOSTAPP_IMG}
}
