DESCRIPTION = "Docker data disk image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
	file://Dockerfile \
	file://entry.sh \
	file://balena-apps.inc \
	"

S = "${WORKDIR}"
B = "${S}/build"

inherit deploy
require docker-disk.inc
require recipes-containers/balena-supervisor/balena-supervisor.inc

# By default pull balena-supervisor
TARGET_APP ?= "${SUPERVISOR_APP}"
TARGET_VERSION ?= "${SUPERVISOR_VERSION}"

PARTITION_SIZE ?= "192"
FS_BLOCK_SIZE ?= "4k"

PV = "${HOSTOS_VERSION}"

RDEPENDS_${PN} = "balena"

BALENA_API_ENV ?= "balena-cloud.com"
BALENA_ADMIN ?= "balena_os"

do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile () {
	# Some sanity first
	if [ -z "${SUPERVISOR_APP}" ] || [ -z "${SUPERVISOR_VERSION}" ]; then
		bbfatal "docker-disk: SUPERVISOR_APP and/or SUPERVISOR_VERSION not set."
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
	cp "${TOPDIR}/../balena-yocto-scripts/automation/include/balena-api.inc" "${WORKDIR}/"

	# Generate the data filesystem
	RANDOM=$$
	_image_name="docker-disk-$RANDOM"
	_container_name="docker-disk-$RANDOM"
	$DOCKER rmi -f ${_image_name} > /dev/null 2>&1 || true
	$DOCKER build -t ${_image_name} -f ${WORKDIR}/Dockerfile ${WORKDIR}
	$DOCKER run --privileged --rm \
		-e BALENA_STORAGE=${BALENA_STORAGE} \
		-e USER_ID=$(id -u) -e USER_GID=$(id -u) \
		-e SUPERVISOR_APP="${SUPERVISOR_APP}" \
		-e SUPERVISOR_VERSION="${SUPERVISOR_VERSION}" \
		-e HELLO_REPOSITORY="${HELLO_REPOSITORY}" \
		-e HOSTAPP_PLATFORM="${HOSTAPP_PLATFORM}" \
		-e BALENA_API_ENV="${BALENA_API_ENV}" \
		-e PARTITION_SIZE="${PARTITION_SIZE}" \
		-e FS_BLOCK_SIZE="${FS_BLOCK_SIZE}" \
		-e HOSTOS_APPS="${HOSTOS_APPS}" \
		-e HOSTOS_VERSION="${HOSTOS_VERSION}" \
		-e BALENA_ADMIN="${BALENA_ADMIN}" \
		-v /sys/fs/cgroup:/sys/fs/cgroup:ro -v ${B}:/build \
		--name ${_container_name} ${_image_name}
	$DOCKER rmi -f ${_image_name}
}

python __anonymous() {
    import urllib.request
    import json
    import hashlib

    token = d.getVar('BALENAOS_TOKEN')
    apiEnv = d.getVar('BALENA_API_ENV')
    version = d.getVar('HOSTOS_VERSION')
    translation = "v6"
    header = {}
    if token is not None:
        header = {'Authorization': "bearer " + token}

    cksums = []
    apps = d.getVar('HOSTOS_APPS')
    for appName in apps.split():
        url = 'https://api.%s/%s/application?$filter='  \
            'slug%%20eq%%20%%27balena_os/%s%%27' % (apiEnv, translation, appName)
        raw = urllib.request.urlopen(urllib.request.Request(url, headers=header))
        json_obj = json.load(raw)
        appID = json_obj['d'][0]['id']
        url = 'https://api.%s/%s/release?$filter=' \
            '(belongs_to__application%%20eq%%20%%27%s%%27)%%20and%%20' \
            '(release_version%%20eq%%20%%27%s%%27)' % (apiEnv, translation,
                                                       appID, version)
        raw = urllib.request.urlopen(urllib.request.Request(url, headers=header))
        json_obj = json.load(raw)
        cksums.append(hashlib.md5(str(json_obj['d'][0]['composition']).encode('utf-8')).hexdigest())
    d.setVar('HOSTOS_APPS_CKSUMS',str(cksums))
}

# Recompile if the hostos app list or their composition change
do_compile[vardeps] += "HOSTOS_APPS"
do_compile[vardeps] += "HOSTOS_APPS_CKSUMS"

FILES_${PN} = "/usr/lib/balena/balena-healthcheck-image.tar"
do_install () {
	mkdir -p ${D}/usr/lib/balena
	install -m 644 ${B}/balena-healthcheck-image.tar ${D}/usr/lib/balena/balena-healthcheck-image.tar
}

do_deploy () {
	install -m 644 ${B}/apps.json ${DEPLOYDIR}/apps.json
	install -m 644 ${B}/resin-data.img ${DEPLOYDIR}/resin-data.img
}
addtask deploy before do_package after do_install

PACKAGE_ARCH = "${MACHINE_ARCH}"
