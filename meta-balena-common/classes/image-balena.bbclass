#
# Balena images customizations
#

inherit image_types_balena

# When building a Balena OS image, we also generate the kernel modules headers
# and ship them in the deploy directory for out-of-tree kernel modules build
DEPENDS += "coreutils-native jq-native ${@bb.utils.contains('BALENA_DISABLE_KERNEL_HEADERS', '1', '', 'kernel-modules-headers kernel-devsrc kernel-headers-test', d)}"

# Deploy the license.manifest of the current image we baked
deploy_image_license_manifest () {
    IMAGE_LICENSE_MANIFEST="${LICENSE_DIRECTORY}/${IMAGE_NAME}/license.manifest"
    if [ ! -f "${IMAGE_LICENSE_MANIFEST}" ]; then
        # Pyro and above have renamed this file
        IMAGE_LICENSE_MANIFEST="${LICENSE_DIRECTORY}/${IMAGE_NAME}/image_license.manifest"
    fi
    # XXX support for post morty yocto versions
    # Check if we are running on a poky version which deploys to IMGDEPLOYDIR instead
    # of DEPLOY_DIR_IMAGE (poky morty introduced this change)
    if [ -d "${IMGDEPLOYDIR}" ]; then
        DEPLOY_IMAGE_LICENSE_MANIFEST="${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.license.manifest"
        DEPLOY_SYMLINK_IMAGE_LICENSE_MANIFEST="${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.license.manifest"
    else
        DEPLOY_IMAGE_LICENSE_MANIFEST="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.license.manifest"
        DEPLOY_SYMLINK_IMAGE_LICENSE_MANIFEST="${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.license.manifest"
    fi
    cp -f ${IMAGE_LICENSE_MANIFEST} ${DEPLOY_IMAGE_LICENSE_MANIFEST}
    ln -sf ${IMAGE_NAME}.rootfs.license.manifest ${DEPLOY_SYMLINK_IMAGE_LICENSE_MANIFEST}
}
do_populate_lic_deploy[nostamp] = "1"

# _remove_old_symlinks removes the hddimg symlink
# Recreate it after image is created
fix_hddimg_symlink () {
    if [ -f ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.hddimg ]; then
        ln -s ${IMAGE_NAME}.hddimg ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.hddimg
    fi
}

# Initialize config.json
# Requires 1 argument: Path to destination of config.json
init_config_json() {
   if [ -z ${1} ]; then
       bbfatal "init_config_json: Needs one argument, that has to be a path"
   fi

   echo '{}' > ${1}/config.json

   # Default no to persistent-logging
   echo "$(cat ${1}/config.json | jq -S ".persistentLogging=false")" > ${1}/config.json

   # Default localMode to true
   echo "$(cat ${1}/config.json | jq -S ".localMode=true")" > ${1}/config.json

   # Find board json and extract slug
   json_path=${BALENA_COREBASE}/../../../${MACHINE}.json
   slug=$(jq .slug $json_path)

   # Set deviceType for supervisor
   echo "$(cat ${1}/config.json | jq -S ".deviceType=$slug")" > ${1}/config.json
}

#
# We need run depmod even if the modules are compressed
# Inspired from rootfs.py
#
def check_for_compressed_kernel_modules(modules_dir):
    for root, dirs, files in os.walk(modules_dir, topdown=True):
        for name in files:
            found_ko = name.endswith(".ko.gz") or name.endswith(".ko.xz")
            if found_ko:
                return found_ko
    return False
fakeroot python generate_compressed_kernel_module_deps() {
    import subprocess

    image_rootfs = d.getVar('IMAGE_ROOTFS', True)
    modules_dir = os.path.join(image_rootfs, 'lib', 'modules')

    # if we don't have any modules don't bother to do the depmod
    if not check_for_compressed_kernel_modules(modules_dir):
        bb.note("No Compressed Kernel Modules found, not running depmod")
        return

    kernel_abi_ver_file = oe.path.join(d.getVar('PKGDATA_DIR', True), "kernel-depmod",
                                           'kernel-abiversion')
    if not os.path.exists(kernel_abi_ver_file):
        bb.fatal("No kernel-abiversion file found (%s), cannot run depmod, aborting" % kernel_abi_ver_file)

    kernel_ver = open(kernel_abi_ver_file).read().strip(' \n')
    versioned_modules_dir = os.path.join(image_rootfs, modules_dir, kernel_ver)

    bb.utils.mkdirhier(versioned_modules_dir)

    exec_cmd = ['depmodwrapper', '-a', '-b', image_rootfs, kernel_ver]

    try:
        subprocess.check_output(exec_cmd, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        return("Command '%s' returned %d:\n%s" % (e.cmd, e.returncode, e.output))
}

#
# Cleanup backup files
#
remove_backup_files () {
    BACKUP_FILES="/etc/passwd- /etc/shadow- /etc/group- /etc/gshadow-"
    for file in $BACKUP_FILES; do
        if [ -f "${IMAGE_ROOTFS}$file" ]; then
            rm ${IMAGE_ROOTFS}$file
        fi
    done
}

# We generate the host keys in the state partition
read_only_rootfs_hook_append () {
    # Yocto sets this to a volatile mount but we want the host keys persistent
    # in the state partition
    sed -i -e \
	's#^SYSCONFDIR.*$#SYSCONFDIR=\${SYSCONFDIR:-/etc/ssh/hostkeys}#' \
        ${IMAGE_ROOTFS}/etc/default/ssh
}

# Generate the boot partition directory and deploy it to rootfs
resin_boot_dirgen_and_deploy () {
    echo "Generating work directory for resin-boot partition..."
    rm -rf ${BALENA_BOOT_WORKDIR}
    for BALENA_BOOT_PARTITION_FILE in ${BALENA_BOOT_PARTITION_FILES}; do
        echo "Handling $BALENA_BOOT_PARTITION_FILE ."

        # Check for item format
        case $BALENA_BOOT_PARTITION_FILE in
            *:*) ;;
            *) bbfatal "Some items in BALENA_BOOT_PARTITION_FILES ($BALENA_BOOT_PARTITION_FILE) are not in the 'src:dst' format."
        esac

        # Compute src and dst
        src="$(echo ${BALENA_BOOT_PARTITION_FILE} | awk -F: '{print $1}')"
        if [ -z "${src}" ]; then
            bbfatal "An entry in BALENA_BOOT_PARTITION_FILES has no source. Entries need to be in the \"src:dst\" format where only \"dst\" is optional. Failed entry: \"$BALENA_BOOT_PARTITION_FILE\"."
        fi
        dst="$(echo ${BALENA_BOOT_PARTITION_FILE} | awk -F: '{print $2}')"
        if [ -z "${dst}" ]; then
            dst="/${src}" # dst was omitted
        fi
        case $src in
            /* )
                # Use absolute src paths as they are
                ;;
            *)
                # Relative src paths are considered relative to deploy dir
                src="${DEPLOY_DIR_IMAGE}/$src"
                ;;
        esac

        # Check that dst is an absolute path and assess if it should be a directory
        case $dst in
            /*)
                # Check if dst is a directory. Directory path ends with '/'.
                case $dst in
                    */) dst_is_dir=true ;;
                     *) dst_is_dir=false ;;
                esac
                ;;
             *) bbfatal "$dst in BALENA_BOOT_PARTITION_FILES is not an absolute path."
        esac

        # Check src type and existence
        if [ -d "$src" ]; then
            if ! $dst_is_dir; then
                bbfatal "You can't copy a directory to a file. You requested to copy $src in $dst."
            fi
            sources="$(find $src -maxdepth 1 -type f)"
        elif [ -f "$src" ]; then
            sources="$src"
        else
            bbfatal "$src is an invalid path referenced in BALENA_BOOT_PARTITION_FILES."
        fi

        # Normalize paths
        dst=$(realpath -ms $dst)
        if $dst_is_dir && [ ! "$dst" = "/" ]; then
            dst="$dst/" # realpath removes last '/' which we need to instruct mcopy that destination is a directory
        fi
        src=$(realpath -m $src)

        for src in $sources; do
            echo "Copying $src -> $dst ..."
            # Create the directories parent directories in dst
            directory=""
            for path_segment in $(echo ${BALENA_BOOT_WORKDIR}/${dst} | sed 's|/|\n|g' | head -n -1); do
                if [ -z "$path_segment" ]; then
                    continue
                fi
                directory=$directory/$path_segment
                mkdir -p $directory
            done
            cp -rvfL $src ${BALENA_BOOT_WORKDIR}/$dst
        done
    done
    echo "${IMAGE_NAME}" > ${BALENA_BOOT_WORKDIR}/image-version-info
    init_config_json ${BALENA_BOOT_WORKDIR}

    # Keep this after everything is ready in the resin-boot directory
    find ${BALENA_BOOT_WORKDIR} -xdev -type f \
        ! -name ${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT} \
        ! -name config.json \
        -exec md5sum {} \; | sed "s#${BALENA_BOOT_WORKDIR}##g" | \
        sort -k2 > ${BALENA_BOOT_WORKDIR}/${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT}

    echo "Install resin-boot in the rootfs..."
    cp -rvf ${BALENA_BOOT_WORKDIR} ${IMAGE_ROOTFS}/${BALENA_BOOT_FS_LABEL}

	# This is a sanity check
	# When updating the hostOS we are using atomic operations for copying new
	# files in the boot partition. This requires twice the size of a file with
	# every copy operation. This means that the boot partition needs to have
	# available at least free space as much as the largest file deployed.
	# First Calculate size of the data
	DATA_SECTORS=$(expr $(du --apparent-size -ks ${BALENA_BOOT_WORKDIR} | cut -f 1) \* 2)
	# Calculate fs overhead
	DIR_BYTES=$(expr $(find ${BALENA_BOOT_WORKDIR} | tail -n +2 | wc -l) \* 32)
	DIR_BYTES=$(expr $DIR_BYTES + $(expr $(find ${BALENA_BOOT_WORKDIR} -type d | tail -n +2 | wc -l) \* 32))
	FAT_BYTES=$(expr $DATA_SECTORS \* 4)
	FAT_BYTES=$(expr $FAT_BYTES + $(expr $(find ${BALENA_BOOT_WORKDIR} -type d | tail -n +2 | wc -l) \* 4))
	DIR_SECTORS=$(expr $(expr $DIR_BYTES + 511) / 512)
	FAT_SECTORS=$(expr $(expr $FAT_BYTES + 511) / 512 \* 2)
	FAT_OVERHEAD_SECTORS=$(expr $DIR_SECTORS + $FAT_SECTORS)
	# Find the largest file and calculate the size in sectors
	LARGEST_FILE_SECTORS=$(expr $(find ${BALENA_BOOT_WORKDIR} -type f -exec du --apparent-size -k {} + | sort -n -r | head -n1 | cut -f1) \* 2)
	if [ -n "$LARGEST_FILE_SECTORS" ]; then
		TOTAL_SECTORS=$(expr $DATA_SECTORS \+ $FAT_OVERHEAD_SECTORS \+ $LARGEST_FILE_SECTORS)
		BOOT_SIZE_SECTORS=$(expr ${BALENA_BOOT_SIZE} \* 2)
		bbnote "resin-boot: FAT overhead $FAT_OVERHEAD_SECTORS sectors, data $DATA_SECTORS sectors, largest file $LARGEST_FILE_SECTORS sectors, boot size $BOOT_SIZE_SECTORS sectors."
		if [ $TOTAL_SECTORS -gt $BOOT_SIZE_SECTORS ]; then
			bbfatal "resin-boot: Not enough space for atomic copy operations."
		fi
	fi
}

QUIRK_FILES ?= " \
    etc/hosts \
    etc/resolv.conf \
    etc/mtab \
    "
resin_root_quirks () {
    # Quirks
    # We need to save some files that the container engine shadows with bind mounts
    # https://docs.docker.com/engine/userguide/networking/default_network/configure-dns/
    # Make sure you run this before packing
    if [ "${QUIRK_FILES}" != "" ];then
        for file in ${QUIRK_FILES}; do
            src="${IMAGE_ROOTFS}/$file"
            dst="${IMAGE_ROOTFS}/quirks/$file"
            if [ -f "$src" ] || [ -L "$src" ]; then
                mkdir -p $(dirname "$dst")
                cp -d "$src" "$dst"
            else
                bbfatal "Quirks: $src doesn't exist."
            fi
        done
    fi
}

resinhup_backwards_compatible_link () {
    if [ -d "${IMGDEPLOYDIR}" ]; then
        # Check if we are running on a poky version which deploys to IMGDEPLOYDIR instead
        # of DEPLOY_DIR_IMAGE (poky morty introduced this change)
        DEPLOY_IMAGE_TAR="${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.tar"
        BALENA_HUP_BUNDLE="${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.resinhup-tar"
    else
        IMAGE_NAME_SUFFIX=".rootfs"
        DEPLOY_IMAGE_TAR="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.tar"
        BALENA_HUP_BUNDLE="${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.resinhup-tar"
    fi
    if [ -f ${DEPLOY_IMAGE_TAR} ]; then
        ln -fsv ${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.tar ${BALENA_HUP_BUNDLE}
    fi
}

add_image_flag_file () {
    echo "DO NOT REMOVE THIS FILE" > ${DEPLOY_DIR_IMAGE}/${BALENA_FLAG_FILE}
}

python resin_boot_sanity_handler() {
  kernel_file = d.getVar('KERNEL_IMAGETYPE', True) + d.getVar('KERNEL_INITRAMFS', True) + d.getVar('MACHINE', True) + '.bin'
  if kernel_file in d.getVar('BALENA_BOOT_PARTITION_FILES', True):
    bb.warn("BalenaOS only supports having the kernel in the root partition in rootfs/boot/KERNEL_IMAGETYPE. Please remove it from BALENA_BOOT_PARTITION_FILES. This will become a fatal warning in a few releases.")
}

python balena_udev_rules_sanity_handler() {
    etc_udev_rules = d.getVar('IMAGE_ROOTFS', True) + '/etc/udev/rules.d/'
    if os.listdir(etc_udev_rules):
        bb.warn("udev rules from /etc/udev/rules.d/*.rules will not be used. Please install them in /lib/udev/rules.d/. /etc/udev/rules.d will be bind mounted for os-udevrules")
        bb.warn("Found the following rules in /etc/udev/rules.d/: " + str(os.listdir(etc_udev_rules)))
}

def get_rev(path):
    import subprocess
    cmd = 'git log -n1 --format=format:%h '
    rev = subprocess.Popen('cd ' + path + ' ; ' + cmd, stdout=subprocess.PIPE, shell=True).communicate()[0]
    if sys.version_info.major >= 3 :
        rev = rev.decode()
    return rev

def get_rel_path_rev(layer, rel, d):
    targetrev = "unknown"
    targetpath = get_rel_path(layer, rel, d)
    if targetpath:
        targetrev = get_rev(targetpath)
    return targetrev

# Returns a path computed by joining 'rel' to the first layer in 'layers' found
# in BBLAYERS
def get_rel_path(layers, rel, d):
    bblayers = d.getVar("BBLAYERS", True)
    for layer in layers:
        layerpath = filter(lambda x: x.endswith(layer), bblayers.split())
        if sys.version_info.major >= 3 :
            layerpath = list(layerpath)
        if layerpath:
            return os.path.join(layerpath[0], rel)
    return ''

def get_slug(d):
    import json
    slug = "unknown"
    machine = d.getVar("MACHINE", True)
    resinboardpath = get_rel_path(['meta-resin-common','meta-balena-common'], '../../../', d)
    if not resinboardpath:
        return slug
    jsonfile = os.path.normpath(os.path.join(resinboardpath, machine + ".json"))
    try:
        with open(jsonfile, 'r') as fd:
            machinejson = json.load(fd)
        slug = machinejson['slug']
    except:
        pass
    return slug

# Sets os specific revisions in os-release
python os_release_extra_data() {
    extra_data = []
    resin_board_rev = get_rel_path_rev(['meta-resin-common', 'meta-balena-common'], '../../../', d)
    if resin_board_rev == "unknown":
        bb.warn("Can't find board repository revision. This information will not be available in os-release.")
    meta_resin_rev = get_rel_path_rev(['meta-resin-common', 'meta-balena-common'], '../', d)
    if meta_resin_rev == "unknown":
        bb.warn("Can't find meta-balena repository revision. This information will not be available in os-release.")
    slug = get_slug(d)
    if slug == "unknown":
        bb.warn("Can't detect the slug. This information will not be available in os-release.")
    extra_data = [
        'BALENA_BOARD_REV="{0}"\n'.format(resin_board_rev),
        'META_BALENA_REV="{0}"\n'.format(meta_resin_rev),
        'SLUG="{0}"\n'.format(slug),
    ]
    os_release_file = os.path.join(d.getVar('IMAGE_ROOTFS', True), "etc/os-release")
    with open(os_release_file, 'a') as f:
        f.writelines(extra_data)
}

ROOTFS_POSTPROCESS_COMMAND += " \
    generate_compressed_kernel_module_deps ; \
    add_image_flag_file ; \
    os_release_extra_data ; \
    resin_boot_dirgen_and_deploy ; \
    resin_root_quirks ; \
    resin_boot_sanity_handler ; \
    balena_udev_rules_sanity_handler ; \
    "
IMAGE_POSTPROCESS_COMMAND =+ " \
    deploy_image_license_manifest ; \
    fix_hddimg_symlink ; \
    resinhup_backwards_compatible_link ; \
    "
IMAGE_PREPROCESS_COMMAND += "remove_backup_files ; "
