/*
 * Copyright 2018 balena
 *
 * @license Apache-2.0
 */

"use strict";

const assert = require("assert");
const fse = require("fs-extra");
const { join } = require("path");
const { homedir } = require("os");


async function getJournalLogs(that){
  // there may be quite a lot in the persistant logs, so we want to check if there's any persistant logs first in /var/logs/journal
  let logs = ""
  try{
    logs = await that.context.get().worker.executeCommandInHostOS(
    `journalctl -a --no-pager`,
    that.context.get().link
    )
  }catch(e){
    that.log(`Couldn't retrieve journal logs with error ${e}`)
  }

  const logPath = "/tmp/journal.log";
  fse.writeFileSync(logPath, logs);
  await that.archiver.add(logPath);
} 


module.exports = {
  title: "Unmanaged BalenaOS release suite",
  run: async function (test) {
    // The worker class contains methods to interact with the DUT, such as flashing, or executing a command on the device
    const Worker = this.require("common/worker");

    // The balenaOS class contains information on the OS image to be flashed, and methods to configure it
    const BalenaOS = this.require("components/os/balenaos");

    await fse.ensureDir(this.suite.options.tmpdir);

    // The suite contex is an object that is shared across all tests. Setting something into the context makes it accessible by every test
    this.suite.context.set({
      utils: this.require("common/utils"),
      sshKeyPath: join(homedir(), "id"),
      link: `${this.suite.options.balenaOS.config.uuid.slice(0, 7)}.local`,
      worker: new Worker(this.suite.deviceType.slug, this.getLogger()),
    });

    // Network definitions - here we check what network configuration is selected for the DUT for the suite, and add the appropriate configuration options (e.g wifi credentials)
    if (this.suite.options.balenaOS.network.wired === true) {
      this.suite.options.balenaOS.network.wired = {
        nat: true,
      };
    } else {
      delete this.suite.options.balenaOS.network.wired;
    }
    if (this.suite.options.balenaOS.network.wireless === true) {
      this.suite.options.balenaOS.network.wireless = {
        ssid: this.suite.options.id,
        psk: `${this.suite.options.id}_psk`,
        nat: true,
      };
    } else {
      delete this.suite.options.balenaOS.network.wireless;
    }

    // Create an instance of the balenOS object, containing information such as device type, and config.json options
    this.suite.context.set({
      os: new BalenaOS(
        {
          deviceType: this.suite.deviceType.slug,
          network: this.suite.options.balenaOS.network,
          configJson: {
            uuid: this.suite.options.balenaOS.config.uuid,
            os: {
              sshKeys: [
                await this.context
                  .get()
                  .utils.createSSHKey(this.context.get().sshKeyPath),
              ],
            },
            // persistentLogging is managed by the supervisor and only read at first boot
            persistentLogging: true,
            // Set local mode so we can perform local pushes of containers to the DUT
            localMode: true,
          },
        },
        this.getLogger()
      ),
    });

    // Register a teardown function execute at the end of the test, regardless of a pass or fail
    this.suite.teardown.register(() => {
      this.log("Worker teardown");
      return this.context.get().worker.teardown();
    });

    this.log("Setting up worker");


    this.suite.teardown.register(async() => {
      this.log("Retreiving journal logs...");
      await getJournalLogs(this)
    })

    // Create network AP on testbot
    await this.context
      .get()
      .worker.network(this.suite.options.balenaOS.network);

    // Unpack OS image .gz
    await this.context.get().os.fetch();

    // Configure OS image
    await this.context.get().os.configure();

    // Flash the DUT
    await this.context.get().worker.off(); // Ensure DUT is off before starting tests
    await this.context.get().worker.flash(this.context.get().os.image.path);
    await this.context.get().worker.on();

    this.log("Waiting for device to be reachable");
    assert.equal(
      await this.context
        .get()
        .worker.executeCommandInHostOS(
          "cat /etc/hostname",
          this.context.get().link
        ),
      this.context.get().link.split(".")[0],
      "Device should be reachable"
    );
  },
  tests: [
    "./tests/fingerprint",
    "./tests/os-release",
    "./tests/chrony",
    "./tests/kernel-overlap",
    "./tests/bluetooth",
    "./tests/healthcheck",
    "./tests/variables",
    "./tests/led",
    "./tests/config-json",
    "./tests/boot-splash",
    "./tests/connectivity",
    "./tests/engine-healthcheck",
    "./tests/udev",
    "./tests/device-tree",
  ],
};
