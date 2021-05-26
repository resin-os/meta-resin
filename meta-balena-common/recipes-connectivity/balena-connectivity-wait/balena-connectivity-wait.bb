DESCRIPTION = "balena full network connectivity checker"
SECTION = "console/utils"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${RESIN_COREBASE}/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://balena-connectivity-wait \
    file://balena-connectivity-wait.service \
    file://balena-connectivity-wait.target \
    "
S = "${WORKDIR}"

inherit allarch systemd

PACKAGES = "${PN}"

SYSTEMD_SERVICE_${PN} = " \
	balena-connectivity-wait.service \
	balena-connectivity-wait.target \
	"

do_install() {
    install -d ${D}${bindir}
    install -m 0775 ${WORKDIR}/balena-connectivity-wait ${D}${bindir}/balena-connectivity-wait

    if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -c -m 0644 ${WORKDIR}/balena-connectivity-wait.service ${D}${systemd_unitdir}/system
        install -c -m 0644 ${WORKDIR}/balena-connectivity-wait.target ${D}${systemd_unitdir}/system
        sed -i -e 's,@BASE_BINDIR@,${base_bindir},g' \
        -e 's,@BINDIR@,${bindir},g' \
            ${D}${systemd_unitdir}/system/balena-connectivity-wait.service
    fi
}
