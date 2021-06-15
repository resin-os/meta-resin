FILESEXTRAPATHS_prepend := "${THISDIR}/balena-files:"

SRC_URI_append = " \
    file://cloud-public-sshkeys \
    file://ssh_keys_merger \
    file://ssh.service \
"

SYSTEMD_SERVICE_${PN}-sshd += "sshdgenkeys.service"

# Have a dedicated user for running AuthorizedKeysCommand
USERADD_PARAM_${PN}-sshd_append = "; --system --no-create-home --home-dir / --shell /bin/false --user-group sshd-authcommands"

FILES_${PN}-sshd += " \
    ${libexecdir}/${BPN}/cloud-public-sshkeys \
    ${sysconfdir}/avahi/services/ssh.service \
    ${sysconfdir}/systemd/system/sshdgenkeys.service.d/sshgenkeys.conf \
    ${sbindir}/ssh_keys_merger \
"

do_install_append () {
    # Advertise SSH service using an avahi service file
    mkdir -p ${D}/etc/avahi/services/
    install -m 0644 ${WORKDIR}/ssh.service ${D}/etc/avahi/services

    # SSH keys merger tool for custom SSH keys
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/ssh_keys_merger ${D}${sbindir}

    # Create config files for read-only rootfs with custom paths for host keys
    install -d ${D}${sysconfdir}/ssh
    install -m 644 ${D}${sysconfdir}/ssh/sshd_config ${D}${sysconfdir}/ssh/sshd_config_readonly
    sed -i '/HostKey/d' ${D}${sysconfdir}/ssh/sshd_config_readonly
    echo "HostKey /etc/ssh/hostkeys/ssh_host_rsa_key" >> ${D}${sysconfdir}/ssh/sshd_config_readonly
    echo "HostKey /etc/ssh/hostkeys/ssh_host_dsa_key" >> ${D}${sysconfdir}/ssh/sshd_config_readonly
    echo "HostKey /etc/ssh/hostkeys/ssh_host_ecdsa_key" >> ${D}${sysconfdir}/ssh/sshd_config_readonly
    echo "HostKey /etc/ssh/hostkeys/ssh_host_ed25519_key" >> ${D}${sysconfdir}/ssh/sshd_config_readonly

    echo "# Get public SSH keys from the API when available" >> ${D}${sysconfdir}/ssh/sshd_config_readonly
    echo "AuthorizedKeysCommand ${libexecdir}/${BPN}/cloud-public-sshkeys %u" >> ${D}${sysconfdir}/ssh/sshd_config_readonly
    echo "AuthorizedKeysCommandUser sshd-authcommands" >> ${D}${sysconfdir}/ssh/sshd_config_readonly

    install -D -m 0755 ${WORKDIR}/cloud-public-sshkeys ${D}${libexecdir}/${BPN}/cloud-public-sshkeys

    # Development version allows PasswordAuthentication
    cp ${D}${sysconfdir}/ssh/sshd_config_readonly ${D}${sysconfdir}/ssh/sshd_config_development
    # Development version allows empty passwords
    sed -i 's/^[#[:space:]]*PermitEmptyPasswords.*/PermitEmptyPasswords yes/' ${D}${sysconfdir}/ssh/sshd_config_development
    # Development version allows root logins
    sed -i 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' ${D}${sysconfdir}/ssh/sshd_config_development
    # Disable PasswordAuthentication for production builds.
    sed -i 's/^[#[:space:]]*PasswordAuthentication yes*/PasswordAuthentication no/' ${D}${sysconfdir}/ssh/sshd_config_readonly
}

# We need dropbear to be able to migrate host keys in the update hooks
RCONFLICTS_${PN} = ""
RCONFLICTS_${PN}-sshd = ""
