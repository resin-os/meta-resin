SUMMARY = "User-mode networking for unprivileged network namespaces."
DESCRIPTION = "slirp4netns allows connecting a network namespace to the \
Internet in a completely unprivileged way, by connecting a TAP device in a \
network namespace to the usermode TCP/IP stack ("slirp")."

LICENSE = "GPLv2+"
LIC_FILES_CHKSUM = "file://COPYING;md5=1e2efd29c201480c6be2744d9edade26"

SRCREV = "4d38845e2e311b684fc8d1c775c725bfcd5ddc27"
SRC_URI = "git://github.com/rootless-containers/slirp4netns.git;nobranch=1"

DEPENDS = "glib-2.0 libcap libseccomp"

S = "${WORKDIR}/git"

inherit autotools pkgconfig

BBCLASSEXTEND = "native"
