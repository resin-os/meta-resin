SUMMARY = "Resin Package Group"
LICENSE = "Apache-2.0"

PR = "r1"

inherit packagegroup

RDEPENDS_${PN} = " \
    ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd-analyze', '', d)} \
    ${BALENA_INIT_PACKAGE} \
    ${BALENA_MOUNTS} \
    ${BALENA_REGISTER} \
    chrony \
    chronyc \
    libnss-ato \
    resin-extra-udev-rules \
    rsync \
    kernel-modules \
    kernel-image-initramfs \
    os-config \
    os-release \
    less \
    development-features \
    "
