DESCRIPTION = "Helpers for OS scripts"
SECTION = "console/utils"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${BALENA_COREBASE}/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

DEPENDS = "time-native"
RDEPENDS_${PN}-fs = "e2fsprogs-tune2fs mtools"

SRC_URI = " \
    file://os-helpers-fs \
    file://os-helpers-logging \
    file://os-helpers-time \
"
S = "${WORKDIR}"

inherit allarch

PACKAGES = "${PN}-fs ${PN}-logging ${PN}-time"
PACKAGES_class-native = "${PN}-engine"

do_install() {
    install -d ${D}${libexecdir}
    install -m 0775 \
        ${WORKDIR}/os-helpers-fs \
        ${WORKDIR}/os-helpers-logging \
        ${WORKDIR}/os-helpers-time \
        ${D}${libexecdir}
}

do_install_class-native() {
    install -d ${D}${libexecdir}
    install -m 0775 \
        "${TOPDIR}/../balena-yocto-scripts/automation/include/balena-docker.inc" \
        ${D}${libexecdir}
}

FILES_${PN}-fs = "${libexecdir}/os-helpers-fs"
FILES_${PN}-logging = "${libexecdir}/os-helpers-logging"
FILES_${PN}-time = "${libexecdir}/os-helpers-time"
FILES_${PN}-engine = "${libexecdir}/balena-docker.inc"

BBCLASSEXTEND = "native"
