inherit deploy

# Add custom resin fields
OS_RELEASE_FIELDS_append = " BALENA_BOARD_REV META_BALENA_REV SLUG MACHINE META_BALENA_VERSION"

# Simplify VERSION output
VERSION = "${HOSTOS_VERSION}"
VERSION_ID = "${HOSTOS_VERSION}"

META_BALENA_VERSION = "${DISTRO_VERSION}"

#
# Add quotes around values not matching [A-Za-z0-9]*
# Failing to do so will confuse the container engine
#
python do_fix_quotes () {
    import re
    lines = open(d.expand('${B}/os-release'), 'r').readlines()
    with open(d.expand('${B}/os-release'), 'w') as f:
        for line in lines:
            field = line.split('=')[0].strip()
            value = line.split('=')[1].strip()
            match = re.match(r"^[A-Za-z0-9]*$", value)
            match_quoted = re.match(r"^\".*\"$", value)
            if not match and not match_quoted:
                value = '"' + value + '"'
            if field == "VERSION_ID":
                # poky does the right thing (converts '+' to '-' in VERSION ID)
                # as per os-release(5) documentation. We want this reverted as
                # we need VERSION_ID to be semver compliant.
                value = value.replace('-rev', '+rev')
            f.write('{0}={1}\n'.format(field, value))

}
addtask fix_quotes after do_compile before do_install

do_deploy() {
    # Issue #906
    # Make the os-release available in the deploy directory as well so we can
    # include it in the boot partition
    install -m 644 ${D}/etc/os-release ${DEPLOYDIR}/os-release
}
addtask do_deploy before do_package after do_install
