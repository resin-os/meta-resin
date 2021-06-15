do_install_prepend() {
    sed -i '/^\[Unit\]/a ConditionPathExists=/var/volatile/development-features' ${WORKDIR}/serial-getty@.service
    sed -i '/^\[Unit\]/a After=development-features.service' ${WORKDIR}/serial-getty@.service
    sed -i '/^\[Unit\]/a Requires=development-features.service' ${WORKDIR}/serial-getty@.service
}
