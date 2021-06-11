/*
 * Copyright 2018 balena
 *
 * @license Apache-2.0
 */

"use strict";

const Bluebird = require("bluebird");
const fse = require("fs-extra");
const { join } = require("path");
const { homedir } = require("os");
const { exec } = require("mz/child_process");

module.exports = {
  title: "Managed BalenaOS release suite",
  run: async function () {
    const Worker = this.require("common/worker");
    const BalenaOS = this.require("components/os/balenaos");
    const Balena = this.require("components/balena/sdk");
    // used for `preload`
    const CLI = this.require("components/balena/cli");

    await fse.ensureDir(this.suite.options.tmpdir);

    // add objects to the context, so that they can be used across all the tests in this suite
    this.suite.context.set({
      cloud: new Balena(this.suite.options.balena.apiUrl, this.getLogger()),
      balena: {
        application: this.suite.options.id,
        organization: this.suite.options.balena.organization,
        sshKey: { label: this.suite.options.id },
      },
      cli: new CLI(this.getLogger()),
      sshKeyPath: join(homedir(), "id"),
      utils: this.require("common/utils"),
      worker: new Worker(this.suite.deviceType.slug, this.getLogger()),
    });

    // Network definitions - these are given to the testbot via the config sent via the config.js
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

    // login
    this.log("Logging into balena with balenaSDK");
    await this.context
      .get()
      .cloud.balena.auth.loginWithToken(this.suite.options.balena.apiKey);

    // create a balena application
    this.log("Creating application in cloud...");
    await this.context.get().cloud.balena.models.application.create({
      name: this.context.get().balena.application,
      deviceType: this.suite.deviceType.slug,
      organization: this.context.get().balena.organization,
    });

    // remove application when tests are done
    this.suite.teardown.register(() => {
      this.log("Removing application");
      return this.context
        .get()
        .cloud.balena.models.application.remove(
          this.context.get().balena.application
        );
    });

    // Push a single container application
    this.log(`Cloning getting started repo...`);
    this.suite.context.set({
      appPath: `${__dirname}/app`
    })
    await exec(
      `git clone https://github.com/balena-io-examples/balena-node-hello-world.git ${this.context.get().appPath}`
    );
    this.log(`Pushing release to app...`);
    const initialCommit = await this.context.get().cloud.pushReleaseToApp(this.context.get().balena.application, `${__dirname}/app`)
    this.suite.context.set({
      balena: {
        initialCommit: initialCommit
      }
    })

    // create an ssh key, so we can ssh into DUT later
    await this.context
      .get()
      .cloud.balena.models.key.create(
        this.context.get().balena.sshKey.label,
        await this.context
          .get()
          .utils.createSSHKey(this.context.get().sshKeyPath)
      );
    this.suite.teardown.register(() => {
      return Bluebird.resolve(
        this.context
          .get()
          .cloud.removeSSHKey(this.context.get().balena.sshKey.label)
      );
    });

    // generate a uuid
    this.suite.context.set({
      balena: {
        uuid: this.context.get().cloud.balena.models.device.generateUniqueKey(),
      },
    });

    this.suite.context.set({
      os: new BalenaOS(
        {
          deviceType: this.suite.deviceType.slug,
          network: this.suite.options.balenaOS.network,
        },
        this.getLogger()
      ),
    });

    // unpack OS
    await this.context.get().os.fetch({
      type: this.suite.options.balenaOS.download.type,
      version: this.suite.options.balenaOS.download.version,
    });

    // get config.json for application
    let config = await this.context
      .get()
      .cloud.balena.models.os.getConfig(this.context.get().balena.application, {
        version: this.context.get().os.contract.version,
      });

    config.uuid = this.context.get().balena.uuid;

    //register the device with the application, add the api key to the config.json
    let deviceApiKey = await this.context
      .get()
      .cloud.balena.models.device.register(
        this.context.get().balena.application,
        this.context.get().balena.uuid
      );
    config.deviceApiKey = deviceApiKey.api_key;

    // get newly registered device id, add to config.json
    await Bluebird.delay(1000 * 10);
    let devId = await this.context
      .get()
      .cloud.balena.models.device.get(this.context.get().balena.uuid);
    config.deviceId = devId.id;

    // get ready to populate DUT image config.json with the attributes we just generated
    this.context.get().os.addCloudConfig(config);


    // Teardown the worker when the tests end
    this.suite.teardown.register(() => {
      this.log("Removing image");
      fse.unlinkSync("/data/image"); // Delete the unpacked an modified image from the testbot cache to prevent use in the next suite
      this.log("Worker teardown");
      return this.context.get().worker.teardown();
    });


    // preload image with the single container application
    this.log(`Device uuid should be ${this.context.get().balena.uuid}`)
    this.log("Preloading image...");
    await this.context.get().os.configure();
    await this.context.get().cli.preload(this.context.get().os.image.path, {
      app: this.context.get().balena.application,
      commit: initialCommit,
      pin: true,
    });

    this.log("Setting up worker");
    await this.context
      .get()
      .worker.network(this.suite.options.balenaOS.network);
    
    await this.context.get().worker.off();
    await this.context.get().worker.flash(this.context.get().os.image.path);
    await this.context.get().worker.on();

    this.log("Waiting for device to be reachable");
    await this.context.get().utils.waitUntil(async() => {
      return await this.context
        .get()
        .cloud.balena.models.device.isOnline(this.context.get().balena.uuid) === true;
    });

    this.log("Device is online and provisioned successfully");
    await this.context.get().utils.waitUntil(async () => {
      this.log("Trying to ssh into device");
      let hostname = await this.context
      .get()
      .cloud.executeCommandInHostOS(
        "cat /etc/hostname",
        this.context.get().balena.uuid
      )
      return hostname === this.context.get().balena.uuid.slice(0, 7)
    }, false);

    this.log("Unpinning");
    await this.context.get().utils.waitUntil(async () => {
      this.log(`Unpinning device from release`)
      await this.context
      .get()
      .cloud.balena.models.device.trackApplicationRelease(
        this.context.get().balena.uuid
      );

      let unpinned = await this.context
      .get()
      .cloud.balena.models.device.isTrackingApplicationRelease(this.context.get().balena.uuid)

      return unpinned
    }, false);

  },
  tests: [
    "./tests/preload",
    "./tests/supervisor",
    "./tests/multicontainer",
  ],
};
