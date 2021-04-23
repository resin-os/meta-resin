SUMMARY = "Resin hostapp rootfs creation tool"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://Dockerfile \
    file://create.ext4 \
    file://mkfs.hostapp \
    "

DEPENDS = " \
    balena-native \
    hostapp-update-native \
    e2fsprogs-native \
    "

inherit native balena-engine-rootless

python __anonymous() {
    # Force BALENA_STORAGE to use the machine specific definition even if we
    # are building a native recipe
    machine = d.getVar("MACHINE", True)
    bs_machine = d.getVar("BALENA_STORAGE_" + machine, True)
    if bs_machine:
        d.setVar("BALENA_STORAGE", bs_machine)
}

S = "${WORKDIR}"

do_compile () {
    rm -rf ${B}/work
    mkdir -p ${B}/work

    cp Dockerfile create.* mkfs.hostapp ${B}/work/
    for i in ${B}/work/create.*; do
        sed -i "s/@BALENA_STORAGE@/${BALENA_STORAGE}/g" $i
    done

    IMAGE_ID=$(DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} build ${B}/work | grep -o -E '[a-z0-9]{12}' | tail -n1)
    DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} save "$IMAGE_ID" > ${B}/work/mkfs-hostapp-image.tar
    DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} rmi "$IMAGE_ID"

    sed -i "s/@IMAGE@/${IMAGE_ID}/" ${B}/work/mkfs.hostapp
}

do_install () {
    install -d ${D}/${bindir}
    install ${B}/work/mkfs.hostapp ${D}/${bindir}/

    install -d ${D}/${datadir}
    install ${B}/work/mkfs-hostapp-image.tar ${D}/${datadir}/
}
