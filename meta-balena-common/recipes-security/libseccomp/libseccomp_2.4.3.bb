SUMMARY = "interface to seccomp filtering mechanism"
DESCRIPTION = "The libseccomp library provides and easy to use, platform independent,interface to the Linux Kernel's syscall filtering mechanism: seccomp."
SECTION = "security"
LICENSE = "LGPL-2.1"
LIC_FILES_CHKSUM = "file://LICENSE;beginline=0;endline=1;md5=8eac08d22113880357ceb8e7c37f989f"

SRCREV = "1dde9d94e0848e12da20602ca38032b91d521427"

SRC_URI = "git://github.com/seccomp/libseccomp.git;branch=release-2.4 \
"

COMPATIBLE_HOST_riscv64 = "null"
COMPATIBLE_HOST_riscv32 = "null"

S = "${WORKDIR}/git"

inherit autotools-brokensep pkgconfig

PACKAGECONFIG ??= ""
PACKAGECONFIG[python] = "--enable-python, --disable-python, python"

DISABLE_STATIC = ""

FILES_${PN} = "${bindir} ${libdir}/${BPN}.so*"

BBCLASSEXTEND = "native"
