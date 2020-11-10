DESCRIPTION = "Docker data disk image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
	file://Dockerfile \
	file://entry.sh \
	"

S = "${WORKDIR}"
B = "${S}/build"

inherit deploy
require docker-disk.inc
require recipes-containers/balena-supervisor/balena-supervisor.inc

# By default pull balena-supervisor
TARGET_REPOSITORY ?= "${SUPERVISOR_REPOSITORY}"
TARGET_TAG ?= "${SUPERVISOR_TAG}"

PARTITION_SIZE ?= "192"
FS_BLOCK_SIZE ?= "4k"

python () {
    import re
    repo = d.getVar("TARGET_REPOSITORY", True)
    tag = d.getVar("TARGET_TAG", True)
    pv = re.sub(r"[^a-z0-9A-Z_.-]", "_", "%s-%s" % (repo,tag))
    d.setVar('PV', pv)
}

PV = "${TARGET_TAG}"

RDEPENDS_${PN} = "balena"

do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile () {
	# Some sanity first
	if [ -z "${TARGET_REPOSITORY}" ] || [ -z "${TARGET_TAG}" ]; then
		bbfatal "docker-disk: TARGET_REPOSITORY and/or TARGET_TAG not set."
	fi
	if [ -z "${PARTITION_SIZE}" ]; then
		bbfatal "docker-disk: PARTITION_SIZE needs to have a value (megabytes)."
	fi

	# At this point we really need internet connectivity for building the
	# docker image
	if [ "x${@connected(d)}" != "xyes" ]; then
		bbfatal "docker-disk: Can't compile as there is no internet connectivity on this host."
	fi

	# We force the PATH to be the standard linux path in order to use the host's
	# docker daemon instead of the result of docker-native. This avoids version
	# mismatches
	DOCKER=$(PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" which docker)

	# Generate the data filesystem
	RANDOM=$$
	_image_name="docker-disk-$RANDOM"
	_container_name="docker-disk-$RANDOM"
	$DOCKER rmi ${_image_name} > /dev/null 2>&1 || true
	$DOCKER build -t ${_image_name} -f ${WORKDIR}/Dockerfile ${WORKDIR}
	$DOCKER run --privileged --rm \
		-e BALENA_STORAGE=${BALENA_STORAGE} \
		-e USER_ID=$(id -u) -e USER_GID=$(id -u) \
		-e TARGET_REPOSITORY="${TARGET_REPOSITORY}" \
		-e TARGET_TAG="${TARGET_TAG}" \
		-e HELLO_REPOSITORY="${HELLO_REPOSITORY}" \
		-e HOSTAPP_PLATFORM="${HOSTAPP_PLATFORM}" \
		-e PRIVATE_REGISTRY="${PRIVATE_REGISTRY}" \
		-e PRIVATE_REGISTRY_USER="${PRIVATE_REGISTRY_USER}" \
		-e PRIVATE_REGISTRY_PASSWORD="${PRIVATE_REGISTRY_PASSWORD}" \
		-e PARTITION_SIZE="${PARTITION_SIZE}" \
		-e FS_BLOCK_SIZE="${FS_BLOCK_SIZE}" \
		-v /sys/fs/cgroup:/sys/fs/cgroup:ro -v ${B}:/build \
		--name ${_container_name} ${_image_name}
	$DOCKER rmi ${_image_name}
}

FILES_${PN} = "/usr/lib/balena/balena-healthcheck-image.tar"
do_install () {
	mkdir -p ${D}/usr/lib/balena
	install -m 644 ${B}/balena-healthcheck-image.tar ${D}/usr/lib/balena/balena-healthcheck-image.tar
}

do_deploy () {
	install -m 644 ${B}/resin-data.img ${DEPLOYDIR}/resin-data.img
}
addtask deploy before do_package after do_install

PACKAGE_ARCH = "${MACHINE_ARCH}"
