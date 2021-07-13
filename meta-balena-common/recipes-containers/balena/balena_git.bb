HOMEPAGE = "https://www.balena.io/"
SUMMARY = "A Moby-based container engine for IoT"
DESCRIPTION = "Balena is a new container engine purpose-built for embedded \
and IoT use cases and compatible with Docker containers. Based on Docker’s \
Moby Project, balena supports container deltas for 10-70x more efficient \
bandwidth usage, has 3.5x smaller binaries, uses RAM and storage more \
conservatively, and focuses on atomicity and durability of container \
pulling."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=4859e97a9c7780e77972d989f0823f28"

inherit systemd go pkgconfig useradd

BALENA_VERSION = "19.03.18"
BALENA_BRANCH= "master"

SRCREV = "840aacc77b6c600b3b929fe9e4d9356a322b9e5b"
SRC_URI = "\
	git://github.com/balena-os/balena-engine.git;branch=${BALENA_BRANCH};destsuffix=git/src/import \
	file://balena.service \
	file://balena-host.service \
	file://balena-host.socket \
	file://balena-healthcheck \
	file://var-lib-docker.mount \
	file://balena.conf.systemd \
	file://balena-tmpfiles.conf \
	file://0001-imporve-hardcoded-CC-on-cross-compile-docker-ce.patch \
	"
S = "${WORKDIR}/git"

PV = "${BALENA_VERSION}+git${SRCREV}"

SECURITY_CFLAGS = "${SECURITY_NOPIE_CFLAGS}"
SECURITY_LDFLAGS = ""

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE_${PN} = "balena.service balena-host.socket var-lib-docker.mount"
GO_IMPORT = "import"
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM_${PN} = "-r balena-engine"

DEPENDS_append_class-target = " systemd"
RDEPENDS_${PN}_class-target = "curl util-linux iptables tini systemd healthdog bash procps-ps"
RRECOMMENDS_${PN} += "kernel-module-nf-nat"

# oe-meta-go recipes try to build go-cross-native
DEPENDS_remove_class-native = "go-cross-native"
DEPENDS_append_class-native = " go-native"

INSANE_SKIP_${PN} += "already-stripped"

FILES_${PN} += " \
	/lib/systemd/system/* \
	/home/root \
	/boot/storage-driver \
	${localstatedir} \
	${bindir} \
	"

DOCKER_PKG="github.com/docker/docker"

do_configure[noexec] = "1"

do_compile() {
	export PATH=${STAGING_BINDIR_NATIVE}/${HOST_SYS}:$PATH

	export GOCACHE="${B}/.cache"
	export GOHOSTOS="linux"
	export GOOS="linux"
	case "${TARGET_ARCH}" in
		x86_64)
			GOARCH=amd64
			;;
		i586|i686)
			GOARCH=386
			;;
		arm)
			GOARCH=${TARGET_ARCH}
			case "${TUNE_PKGARCH}" in
				cortexa*)
					export GOARM=7
					;;
			esac
			;;
		aarch64)
			# ARM64 is invalid for Go 1.4
			GOARCH=arm64
		;;
		*)
			GOARCH="${TARGET_ARCH}"
		;;
	esac
	export GOARCH

	# Set GOPATH. See 'PACKAGERS.md'. Don't rely on
	# docker to download its dependencies but rather
	# use dependencies packaged independently.
	cd ${S}/src/import
	rm -rf .gopath
	mkdir -p .gopath/src/"$(dirname "${DOCKER_PKG}")"
	ln -sf ../../../.. .gopath/src/"${DOCKER_PKG}"
	export GOPATH="${S}/src/import/.gopath:${S}/src/import/vendor:${STAGING_DIR_TARGET}/${prefix}/local/go"

	export CGO_ENABLED="1"

	# Pass the needed cflags/ldflags so that cgo
	# can find the needed headers files and libraries
	export CGO_CFLAGS="${CFLAGS} --sysroot=${STAGING_DIR_TARGET}"
	export CGO_LDFLAGS="${LDFLAGS}  --sysroot=${STAGING_DIR_TARGET}"

	export DOCKER_GITCOMMIT="${SRCREV}"
	export DOCKER_BUILDTAGS="no_buildkit no_btrfs no_cri no_devmapper no_zfs exclude_disk_quota exclude_graphdriver_btrfs exclude_graphdriver_devicemapper exclude_graphdriver_zfs"
	export DOCKER_LDFLAGS="-s"

	VERSION=${BALENA_VERSION} ./hack/make.sh dynbinary-balena
}

do_install() {
	mkdir -p ${D}/${bindir}
	install -m 0755 ${S}/src/import/bundles/dynbinary-balena/balena-engine ${D}/${bindir}/balena-engine
	install -d ${D}/boot
	echo ${BALENA_STORAGE} > ${D}/boot/storage-driver

	ln -sf balena-engine ${D}/${bindir}/balena
	ln -sf balena-engine ${D}/${bindir}/balenad
	ln -sf balena-engine ${D}/${bindir}/balena-containerd
	ln -sf balena-engine ${D}/${bindir}/balena-containerd-shim
	ln -sf balena-engine ${D}/${bindir}/balena-containerd-ctr
	ln -sf balena-engine ${D}/${bindir}/balena-runc
	ln -sf balena-engine ${D}/${bindir}/balena-proxy

	ln -sf balena-engine ${D}/${bindir}/balena-engine-daemon
	ln -sf balena-engine ${D}/${bindir}/balena-engine-containerd
	ln -sf balena-engine ${D}/${bindir}/balena-engine-containerd-shim
	ln -sf balena-engine ${D}/${bindir}/balena-engine-containerd-ctr
	ln -sf balena-engine ${D}/${bindir}/balena-engine-runc
	ln -sf balena-engine ${D}/${bindir}/balena-engine-proxy

	install -d ${D}${systemd_unitdir}/system
	install -m 0644 ${S}/src/import/contrib/init/systemd/balena-engine.socket ${D}/${systemd_unitdir}/system

	install -m 0644 ${WORKDIR}/balena.service ${D}/${systemd_unitdir}/system
	sed -i "s/@BALENA_STORAGE@/${BALENA_STORAGE}/g" ${D}${systemd_unitdir}/system/balena.service

	install -m 0644 ${WORKDIR}/balena-host.service ${D}/${systemd_unitdir}/system
	sed -i "s/@BALENA_STORAGE@/${BALENA_STORAGE}/g" ${D}${systemd_unitdir}/system/balena-host.service
	install -m 0644 ${WORKDIR}/balena-host.socket ${D}/${systemd_unitdir}/system

	install -m 0644 ${WORKDIR}/var-lib-docker.mount ${D}/${systemd_unitdir}/system

	mkdir -p ${D}/usr/lib/balena
	install -m 0755 ${WORKDIR}/balena-healthcheck ${D}/usr/lib/balena/balena-healthcheck

	if ${@bb.utils.contains('DISTRO_FEATURES','development-image','true','false',d)}; then
		install -d ${D}${sysconfdir}/systemd/system/balena.service.d
		install -c -m 0644 ${WORKDIR}/balena.conf.systemd ${D}${sysconfdir}/systemd/system/balena.service.d/balena.conf
		sed -i "s/@BALENA_STORAGE@/${BALENA_STORAGE}/g" ${D}${sysconfdir}/systemd/system/balena.service.d/balena.conf
	fi

	install -d ${D}/home/root/.docker
	ln -sf .docker ${D}/home/root/.balena
	ln -sf .docker ${D}/home/root/.balena-engine

	install -d ${D}${localstatedir}/lib/docker
	ln -sf docker ${D}${localstatedir}/lib/balena
	ln -sf docker ${D}${localstatedir}/lib/balena-engine

	install -d ${D}${sysconfdir}/tmpfiles.d
	install -m 0644 ${WORKDIR}/balena-tmpfiles.conf ${D}${sysconfdir}/tmpfiles.d/
}

do_install_append_class-native() {
        install -d ${D}${bindir}
        install -m 0755 ${S}/src/import/contrib/dockerd-rootless.sh ${D}${bindir}/balenad-rootless.sh
        sed -i "s/dockerd/balenad/g" ${D}${bindir}/balenad-rootless.sh
}

BBCLASSEXTEND = " native"
