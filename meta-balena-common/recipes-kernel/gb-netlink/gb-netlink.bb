SUMMARY = "Out-of-tree Greybus module to communicate with the Linux Greybus facilities through userspace"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://LICENSE;md5=e8c1458438ead3c34974bc0be3a03ed6"

inherit module

SRC_URI = "git://git@github.com/cfriedt/gb-netlink.git;branch=gb_netlink"
SRCREV = "518363b7bbefe31d65d3e9757e8759e28e5f6917"
S = "${WORKDIR}/git"

EXTRA_OEMAKE += "KERNELDIR='${STAGING_KERNEL_DIR}'"

module_do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/drivers/greybus/
	install -m 0644 *.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/drivers/greybus/
}

KERNEL_MODULE_AUTOLOAD += "gb-netlink"
