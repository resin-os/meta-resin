DESCRIPTION = "Runtime development images features"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${BALENA_COREBASE}/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://development-features \
    file://development-features.service \
    file://development-features.target \
    "
S = "${WORKDIR}"

inherit allarch systemd

SYSTEMD_SERVICE_${PN} = " \
    development-features.service \
    development-features.target \
    "

do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_build[noexec] = "1"

do_install() {
    install -d ${D}${bindir}/
    install -m 0755 ${WORKDIR}/development-features ${D}${bindir}/

    if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
        install -d ${D}${systemd_unitdir}/system/
        install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants/
        install -m 0644 ${WORKDIR}/development-features.service ${D}${systemd_unitdir}/system/
        install -m 0644 ${WORKDIR}/development-features.target ${D}${systemd_unitdir}/system/

        sed -i -e 's,@BASE_BINDIR@,${base_bindir},g' \
            -e 's,@SBINDIR@,${sbindir},g' \
            -e 's,@BINDIR@,${bindir},g' \
            -e 's,@BALENA_STATE_MP@,${BALENA_STATE_MOUNT_POINT},g' \
            ${D}${systemd_unitdir}/system/*.service
    fi
}

FILES_${PN} += "${systemd_unitdir}/system/development-features.target"
