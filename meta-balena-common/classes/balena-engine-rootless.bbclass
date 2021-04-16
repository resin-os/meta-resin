DEPENDS += "balena-native slirp4netns-native os-helpers-native rootlesskit-native"

# Need a short path here as unix sockets paths have a maximum length of 104 characters
ENGINE_DIR ?= "${TOPDIR}/${PN}"
# Make sure these are on a real ext4 filesystem and not inside a container filesystem
# Socket is created in exec-root so path must be short
ENGINE_EXEC_ROOT="${ENGINE_DIR}/r"
ENGINE_DATA_ROOT="${ENGINE_DIR}/d"
ENGINE_SOCK = "${ENGINE_DIR}/balena.sock"
DOCKER_HOST = "unix://${ENGINE_SOCK}"
ENGINE_PIDFILE = "${WORKDIR}/balena-engine.pid"
ENGINE_CLIENT_NAME = "balena"
ENGINE_NAME = "balenad"
ENGINE_CLIENT = "env DOCKER_HOST=${DOCKER_HOST} ${ENGINE_CLIENT_NAME}"

# Older distros (i.e Ubuntu 17.10) do not support seccomp
ENGINE_SLIRP4NETNS_SECCOMP ?= "false"
ENGINE_SLIRP4NETNS_SANDBOX ?= "auto"

do_run_engine() {
    set -x
    mkdir -p "${ENGINE_DIR}"
    if [ -f "${ENGINE_PIDFILE}" ]; then
        # Already running
        return
    fi
    # Make sure newuidmap/newgidmap are used from the host tools as they need to be setuid'ed
    exec env PATH="${HOSTTOOLS_DIR}:${PATH}" XDG_RUNTIME_DIR=${ENGINE_DIR} DOCKERD_ROOTLESS_ROOTLESSKIT_SLIRP4NETNS_SECCOMP=${ENGINE_SLIRP4NETNS_SECCOMP} DOCKERD_ROOTLESS_ROOTLESSKIT_SLIRP4NETNS_SANDBOX=${ENGINE_SLIRP4NETNS_SANDBOX} balenad-rootless.sh --experimental --pidfile ${ENGINE_PIDFILE} -H ${DOCKER_HOST} --exec-root ${ENGINE_EXEC_ROOT} --data-root ${ENGINE_DATA_ROOT}  &
    . "${STAGING_DIR_NATIVE}/usr/libexec/balena-docker.inc"
    balena_docker_wait "${DOCKER_HOST}" "balena" > ${WORKDIR}/temp/log.balenad-rootless-wait-${BB_CURRENTTASK} 2>&1
}

do_stop_engine() {
    set -x
    . "${STAGING_DIR_NATIVE}/usr/libexec/balena-docker.inc"
    balena_docker_stop fail "${ENGINE_PIDFILE}" "${ENGINE_NAME}"
    # Rootless engine may create a non-writable directory, let's fix it
    if [ -d "${ENGINE_DIR}" ]; then
        find ${ENGINE_EXEC_ROOT} -type d -exec chmod 755 {} +
        rm -rf ${ENGINE_DIR}
    fi
}

do_compile_prepend() {
    do_run_engine
}

do_compile_append() {
    do_stop_engine
}

do_run_engine_docker() {
    do_run_engine
}

do_run_engine_hostapp_ext4() {
    do_run_engine
}

IMAGE_CMD_docker_append() {
    do_stop_engine
}

IMAGE_CMD_hostapp-ext4_append() {
    do_stop_engine
}

addtask do_run_engine_docker before do_image_docker after do_rootfs
addtask do_run_engine_hostapp_ext4 before do_image_hostapp_ext4 after do_image_docker

# Do not try to start more than one engine
do_compile[lockfiles] += "${TMPDIR}/balena-engine-rootless.lock"
do_rootfs[lockfiles] += "${TMPDIR}/balena-engine-rootless.lock"
do_image_docker[lockfiles] += "${TMPDIR}/balena-engine-rootless.lock"
do_image_hostapp_ext4[lockfiles] += "${TMPDIR}/balena-engine-rootless.lock"

do_run_engine_docker[nostamp] = "1"
do_run_engine_hostapp_ext4[nostamp] = "1"

do_run_engine_docker[depends] = " \
    os-helpers-native:do_populate_sysroot \
    balena-native:do_populate_sysroot \
    slirp4netns-native:do_populate_sysroot \
    rootlesskit-native:do_populate_sysroot \
    "
