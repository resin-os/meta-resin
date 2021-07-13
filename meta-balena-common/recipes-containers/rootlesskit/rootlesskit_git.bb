HOMEPAGE = "https://github.com/rootless-containers/rootlesskit"
SUMMARY = "Linux native fakeroot using user namespaces"
DESCRIPTION = "Rootlesskit is a linux-native implementation of fakeroot using user namespaces"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit go

RDEPENDS_${PN} = "util-linux"

GO_IMPORT = "github.com/rootless-containers/rootlesskit"
SRC_URI = "git://${GO_IMPORT};nobranch=1"
SRCREV="ce88a431e6a7cf891ebb68b10bfc6a5724b9ae72"

S = "${WORKDIR}/${BPN}/src/${GO_IMPORT}"

do_compile() {
    cd ${S}
    unset GO_LDFLAGS
    unset GOPATH GOROOT
    export GOCACHE="${B}/.cache"
    oe_runmake
}

do_install() {
	install -d ${D}/${bindir}
        install -m 0755 ${S}/bin/rootlesskit ${D}/${bindir}
        install -m 0755 ${S}/bin/rootlesskit-docker-proxy ${D}/${bindir}
        install -m 0755 ${S}/bin/rootlessctl ${D}/${bindir}
}

FILES_${PN} += " \
    /bin/rootlesskit \
    /bin/rootlesskit-docker-proxy \
    /bin/rootlessctl \
"

INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP_${PN} += "already-stripped"

BBCLASSEXTEND = "native"
