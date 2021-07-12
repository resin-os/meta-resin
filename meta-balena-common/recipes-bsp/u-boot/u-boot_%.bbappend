FILESEXTRAPATHS_append := ":${THISDIR}/files"

# We require these uboot config options to be enabled for env_resin.h
SRC_URI += "file://balenaos_uboot.cfg"

SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'osdev-image', '', 'file://balenaos_uboot_prod.cfg', d)}"
SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'osdev-image', 'file://balenaos_uboot_delay.cfg', 'file://balenaos_uboot_nodelay.cfg', d)}"

# Since 11278e3b2c75be80645b9841763a97dbb35daadc u-boot.inc has support
# for ammending the bsp uboot with config fragments. We copy that
# over in meta-balena-common to apply to pre-warrior layers.

DEPENDS += "kern-tools-native"

inherit uboot-config uboot-extlinux-config uboot-sign deploy cml1

# disable u-boot-initial-env as we don't need it and it would
# break do_install without additional changes to do_compile first
# https://github.com/balena-os/poky/commit/d7b8ae3faa9344f2ada22e0402066c2fff5958c6
UBOOT_INITIAL_ENV = ""
ALLOW_EMPTY_${PN}-env = "1"

# returns all the elements from the src uri that are .cfg files
def find_cfgs(d):
    sources=src_patches(d, True)
    sources_list=[]
    for s in sources:
        if s.endswith('.cfg'):
            sources_list.append(s)

    return sources_list

do_configure () {
    if [ -z "${UBOOT_CONFIG}" ]; then
        if [ -n "${UBOOT_MACHINE}" ]; then
            oe_runmake -C ${S} O=${B} ${UBOOT_MACHINE}
        else
            oe_runmake -C ${S} O=${B} oldconfig
        fi
        merge_config.sh -m .config ${@" ".join(find_cfgs(d))}
        cml1_do_configure
    fi
}

do_compile () {
	if [ "${@bb.utils.filter('DISTRO_FEATURES', 'ld-is-gold', d)}" ]; then
		sed -i 's/$(CROSS_COMPILE)ld$/$(CROSS_COMPILE)ld.bfd/g' ${S}/config.mk
	fi

	unset LDFLAGS
	unset CFLAGS
	unset CPPFLAGS

	if [ ! -e ${B}/.scmversion -a ! -e ${S}/.scmversion ]
	then
		echo ${UBOOT_LOCALVERSION} > ${B}/.scmversion
		echo ${UBOOT_LOCALVERSION} > ${S}/.scmversion
	fi

    if [ -n "${UBOOT_CONFIG}" ]
    then
        unset i j k
        for config in ${UBOOT_MACHINE}; do
            i=$(expr $i + 1);
            for type in ${UBOOT_CONFIG}; do
                j=$(expr $j + 1);
                if [ $j -eq $i ]
                then
                    oe_runmake -C ${S} O=${B}/${config} ${config}
                    oe_runmake -C ${S} O=${B}/${config} ${UBOOT_MAKE_TARGET}
                    for binary in ${UBOOT_BINARIES}; do
                        k=$(expr $k + 1);
                        if [ $k -eq $i ]; then
                            cp ${B}/${config}/${binary} ${B}/${config}/u-boot-${type}.${UBOOT_SUFFIX}
                        fi
                    done
                    unset k
                fi
            done
            unset  j
        done
        unset  i
    else
        oe_runmake -C ${S} O=${B} ${UBOOT_MAKE_TARGET}
    fi

}
