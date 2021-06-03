DESCRIPTION = "BalenaOS data store updater"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${BALENA_COREBASE}/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
	file://update-data-store \
	"
S = "${WORKDIR}"

inherit allarch systemd

FILES_${PN} = "${bindir}"

RDEPENDS_${PN} = " \
    balena \
    bash \
    os-helpers-api \
    "

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/update-data-store ${D}${bindir}
}
