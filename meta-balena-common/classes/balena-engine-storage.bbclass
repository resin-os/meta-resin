# Native recipes that decide whether to inherit balena-rootless-engine based
# on BALENA_STORAGE need this class to be globally inherited

python balena_set_engine() {
    # Force BALENA_STORAGE to use the machine specific definition even if we
    # are building a native recipe
    machine = d.getVar("MACHINE", True)
    bs_machine = d.getVar("BALENA_STORAGE_" + machine, True)
    if bs_machine:
        d.setVar("BALENA_STORAGE", bs_machine)
}

addhandler balena_set_engine
balena_set_engine[eventmask] = "bb.event.ConfigParsed"
