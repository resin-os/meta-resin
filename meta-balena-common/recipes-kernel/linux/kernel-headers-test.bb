SUMMARY = "Linux kernel headers test"
DESCRIPTION = "This recipe tests generated kernel headers by running a simple hello-world compile test"
SECTION = "devel/kernel"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://example_module/hello.c \
           file://example_module/Makefile \
           file://Dockerfile"

inherit kernel-arch
ENGINE_CLIENT ?= "docker"
inherit ${@bb.utils.contains('BALENA_STORAGE','overlay2','balena-engine-rootless', '', d)}

# Derived from kernel-arch.bbclass
valid_debian_tuple = "i386 x86 arm aarch64"

def map_DEBIAN_TUPLE(a, d):
    import re

    valid_debian_tuple = d.getVar('valid_debian_tuple').split()

    if re.match('x86', a):
        return 'x86_64-linux-gnu-'
    elif re.match('arm64', a):
        return 'aarch64-linux-gnu-'
    elif re.match('arm', a):
        return 'arm-linux-gnueabi-'
    else:
        bb.error("cannot map '%s' to a debian tuple" % a)

DEBIAN_TUPLE ?= "${@map_DEBIAN_TUPLE(d.getVar('ARCH'), d)}"

do_compile() {
    rm -rf ${B}/work
    mkdir -p ${B}/work
    cp ${DEPLOY_DIR_IMAGE}/kernel_source.tar.gz ${B}/work
    cp ${DEPLOY_DIR_IMAGE}/kernel_modules_headers.tar.gz ${B}/work
    cp "${WORKDIR}"/Dockerfile ${B}/work/
    cp -r "${WORKDIR}"/example_module ${B}/work/
    IMAGE_ID=$(DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} build --build-arg kernel_arch=${ARCH} --build-arg cross_compile_prefix=${DEBIAN_TUPLE} ${B}/work)
    # We don't pipe in previous line so that we can catch errors.
    IMAGE_ID=$(echo "$IMAGE_ID" | grep -o -E '[a-z0-9]{12}' | tail -n1)
    DOCKER_API_VERSION=1.22 ${ENGINE_CLIENT} rmi "$IMAGE_ID"
}

# Explicitly depend on the do_deploy step as we use the deployed artefacts. DEPENDS doesn't cover that
do_compile[depends] += "kernel-devsrc:do_deploy"
do_compile[depends] += "kernel-modules-headers:do_deploy"
