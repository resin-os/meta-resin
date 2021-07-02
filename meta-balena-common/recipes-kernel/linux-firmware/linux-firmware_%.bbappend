PACKAGES =+ "${PN}-rtl8188eu"

FILES_${PN}-rtl8188eu = " \
    /lib/firmware/rtlwifi/rtl8188eu*.bin \
    "

PACKAGES =+ "${PN}-iwlwifi-9260"

FILES_${PN}-iwlwifi-9260 = " \
    ${nonarch_base_libdir}/firmware/iwlwifi-9260-* \
    "

PACKAGES =+ "${PN}-iwlwifi-qu-b0-hr-b0"

FILES_${PN}-iwlwifi-qu-b0-hr-b0 = " \
    ${nonarch_base_libdir}/firmware/iwlwifi-Qu-b0-hr-b0-* \
    "

PACKAGES =+ "${PN}-ibt-19-0-4"

FILES_${PN}-ibt-19-0-4  = " \
    ${nonarch_base_libdir}/firmware/intel/ibt-19-0-4.doc \
    ${nonarch_base_libdir}/firmware/intel/ibt-19-0-4.sfi \
    "

PACKAGES =+ "${PN}-ath10k-qca6174"

FILES_${PN}-ath10k-qca6174 = " \
    ${nonarch_base_libdir}/firmware/ath10k/QCA6174/* \
"

PACKAGES =+ "${PN}-rtl8723b-bt"

FILES_${PN}-rtl8723b-bt = " \
    ${nonarch_base_libdir}/firmware/rtl_bt/rtl8723b_fw.bin \
"

PACKAGES =+ "${PN}-iwlwifi-3168"

FILES_${PN}-iwlwifi-3168 = " \
    ${nonarch_base_libdir}/firmware/iwlwifi-3168-* \
"

PACKAGES =+ "${PN}-ibt-18-16-1"

FILES_${PN}-ibt-18-16-1  = " \
    ${nonarch_base_libdir}/firmware/intel/ibt-18-16-1.sfi \
    ${nonarch_base_libdir}/firmware/intel/ibt-18-16-1.ddc \
"

PACKAGES =+ "${PN}-ralink-nic"

FILES_${PN}-ralink-nic = " \
    ${nonarch_base_libdir}/firmware/rtl_nic/rtl8168g-2.fw \
"

PACKAGES =+ "${PN}-iwlwifi-3160"

FILES_${PN}-iwlwifi-3160 = " \
    ${nonarch_base_libdir}/firmware/iwlwifi-3160-17.ucode \
"

PACKAGES =+ "${PN}-iwlwifi-cc-a0"

FILES_${PN}-iwlwifi-cc-a0 = " \
    ${nonarch_base_libdir}/firmware/iwlwifi-cc-a0-48.ucode \
"

PACKAGES =+ "${PN}-iwlwifi-quz-a0-hr-b0"

FILES_${PN}-iwlwifi-quz-a0-hr-b0 = " \
    ${nonarch_base_libdir}/firmware/iwlwifi-QuZ-a0-hr-b0-48.ucode \
"
