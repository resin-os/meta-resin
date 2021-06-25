/*
 * Copyright 2021 balena
 *
 * @license Apache-2.0
 */

"use strict";

const fs = require("fs");
const fse = require("fs-extra");
const { join } = require("path");
const { homedir } = require("os");
const Docker = require('dockerode');
const exec = require('bluebird').promisify(require('child_process').exec);

// Starts registry, uploads target image to registry
const runRegistry = async (that, seedWithImage) => {
  const docker = new Docker();
  const registryImage = 'registry:2';

  that.log("Pulling registry image");
  await docker.pull(registryImage);

  const container = await docker.createContainer({
    Image: registryImage,
    HostConfig: {
      AutoRemove: true,
      Mounts: [{
        Type: 'tmpfs',
        Target: '/var/lib/registry'
      }],
      PortBindings: {
        "5000/tcp": [{
          "HostPort": "5000",
        }],
      },
    }

  }).then((container) => {
    that.log("Starting registry");
    return container.start();
  });

  that.suite.teardown.register(async () => {
    that.log(`Teardown registry`);
    try {
      await container.kill();
    } catch (err) {
      that.log(`Error removing registry container: ${err}`);
    }
  });

  that.log("Loading image into registry");
  const imageName = await docker.loadImage(seedWithImage)
    .then(res => {
      return new Promise((resolve, reject) => {
        var bufs = [];
        res.on('error', err => reject(err));
        res.on('data', data => bufs.push(data));
        res.on('end', () => resolve(JSON.parse(Buffer.concat(bufs))));
      });
    })
    .then(json => {
      const str = json.stream.split('Loaded image ID: ');
      if (str.length === 2) {
        return str[1].trim();
      }
      throw new Error('failed to parse image name from loadImage stream');
    });

  const image = await docker.getImage(imageName);
  const ref = 'localhost:5000/hostapp';

  await image.tag({ repo: ref, tag: 'latest' });
  const tagged = await docker.getImage(ref);
  const digest = await tagged.push({ ref })
    .then(res => {
      return new Promise((resolve, reject) => {
        var bufs = [];
        res.on('error', err => reject(err));
        res.on('data', data => bufs.push(JSON.parse(data)));
        res.on('end', () => resolve(bufs));
      });
    })
    .then(output => {
      for (let json of output) {
        if (json.error) {
          throw new Error(json.error);
        }
        if (json.aux && json.aux.Digest) {
          return json.aux.Digest;
        }
      }
      throw new Error('no digest');
    });
  await image.remove();

  // this parses the IP of the wlan0 interface which is the gateway for the DUT
  // TODO should this be a common func? Replace this with Robert's PR when merged
  const testbotIP = (await exec(`ip addr | awk '/inet.*wlan0/{print $2}' | cut -d\/ -f1`)).trim();
  const hostappRef = `${testbotIP}:5000/hostapp@${digest}`;
  that.log(`Registry upload complete: ${hostappRef}`);

  that.suite.context.set({
    hup: {
      payload: hostappRef,
    }
  })
}

// Executes the HUP process on the DUT
const doHUP = async (that, test, mode, hostapp, target) => {
  test.comment(`Starting HUP`);

  let hupLog;
  switch (mode) {
    case 'local':
      if (await that.context.get().worker.executeCommandInHostOS(
        `[[ -f ${hostapp} ]] && echo exists`,
        target,
      ) !== 'exists') {
        throw new Error(
          `Target image doesn't exists at location "${hostapp}"`,
        );
      }
      test.comment(`Running: hostapp-update -f ${hostapp}`);
      // TODO do we need to print the output here? No, looks cleaner without it.
      hupLog = await that.context.get().worker.executeCommandInHostOS(
        `hostapp-update -f ${hostapp}`,
        target,
      );
      break;

    case 'image':
      test.comment(`Running: hostapp-update -i ${hostapp}`);
      hupLog = await that.context.get().worker.executeCommandInHostOS(
        `hostapp-update -i ${hostapp}`,
        target,
      );
      break;

    default:
      throw new Error(`Unsupported HUP mode: ${mode}`);
  }

  const hupLogPath = join(that.suite.options.tmpdir, `hup.log`);
  fs.writeFileSync(hupLogPath, hupLog);
  await that.archiver.add(hupLogPath);

  test.comment(`Finished HUP`);
};

// Retrieves balenaOS version
const getOSVersion = async (that, target) => {
  const output = await that.context.get().worker
    .executeCommandInHostOS(
      "cat /etc/os-release",
      target
    );
  let match;
  output
    .split("\n")
    .every(x => {
      if (x.startsWith("VERSION=")) {
        match = x.split("=")[1];
        return false;
      }
      return true;
    })
  return match.replace(/"/g, '');
}

const initDUT = async (that, test, target) => {
  test.comment(`Initializing DUT for HUP test`);

  test.comment(`Flashing DUT`);
  await that.context.get().worker.off();
  await that.context.get().worker.flash(that.context.get().os.image.path);
  await that.context.get().worker.on();

  test.comment(`Waiting for DUT to be reachable`);
  await that.context.get().utils.waitUntil(async () => {
      return (
        (await that.context.get().worker.executeCommandInHostOS(
            '[[ -f /etc/hostname ]] && echo pass || echo fail',
            target,
          )) === 'pass'
      );
    }, true);
  test.comment(`DUT flashed`);

  test.comment(`Configuring DUT to use test suite registry`);
  // TODO rework this after https://github.com/balena-os/meta-balena/pull/2175
  // FIXME we should probably use a shared testbotIP method with the runRegistry helper...
  await that.context.get().worker.executeCommandInHostOS(
    `mount -o remount,rw / && sed -e "s/driver=systemd/driver=systemd --insecure-registry=$(ip route | awk '/default/{print $3}'):5000/" -i /lib/systemd/system/balena-host.service && systemctl daemon-reload && systemctl restart balena-host && mount -o remount,ro /`,
    target,
  );
  test.comment(`DUT ready`);

  that.teardown.register(async () => {
    await that.context.get().hup.archiveLogs(that,
      test, target);
  })
}

const archiveLogs = async (that, test, target) => {
  test.comment(`Archiving HUP artifacts`);

  const rollback = await that.context.get().worker.executeCommandInHostOS(
    `journalctl --no-pager --no-hostname --unit rollback-health`,
    target,
  );
  const rollbackLogs = join(that.suite.options.tmpdir, `rollback-health.log`);
  fs.writeFileSync(rollbackLogs, rollback);
  await that.archiver.add(rollbackLogs);

  const journal = await that.context
    .get()
    .worker.executeCommandInHostOS(
      `journalctl --no-pager --no-hostname --list-boots | awk '{print $1}' | xargs -I{} sh -c 'set -x; journalctl --no-pager --no-hostname -n500 -a -b {};'`,
      target,
    );
  const journalLogs = join(that.suite.options.tmpdir, `journal.log`);
  fs.writeFileSync(journalLogs, journal);
  await that.archiver.add(journalLogs);
}

module.exports = {
  title: "Hostapp update suite",

  run: async function () {
    const Worker = this.require("common/worker");
    const BalenaOS = this.require("components/os/balenaos");
    const Balena = this.require("components/balena/sdk");

    await fse.ensureDir(this.suite.options.tmpdir);

    this.suite.context.set({
      utils: this.require("common/utils"),
      sdk: new Balena(this.suite.options.balena.apiUrl, this.getLogger()),
      sshKeyPath: join(homedir(), "id"),
      link: `${this.suite.options.balenaOS.config.uuid.slice(0, 7)}.local`,
      worker: new Worker(this.suite.deviceType.slug, this.getLogger()),
    });

    // Network definitions
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

    this.suite.context.set({
      hup: {
        doHUP:        doHUP,
        getOSVersion: getOSVersion,
        initDUT:      initDUT,
        runRegistry:  runRegistry,
        archiveLogs:  archiveLogs,
      }
    })

    // Downloads the balenaOS image we hup from
    const path = await this.context.get().sdk.fetchOS(
      this.suite.options.balenaOS.download.version,
      this.suite.deviceType.slug
    );

    this.suite.context.set({
      os: new BalenaOS(
        {
          deviceType: this.suite.deviceType.slug,
          network: this.suite.options.balenaOS.network,
          image: `${path}`,
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
          },
        },
        this.getLogger()
      ),
      hupOs: new BalenaOS(
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
          },
        },
        this.getLogger()
      ),
    });
    this.suite.teardown.register(() => {
      this.log("Worker teardown");
      return this.context.get().worker.teardown();
    });

    this.log("Setting up worker");
    await this.context
      .get()
      .worker.network(this.suite.options.balenaOS.network);

    // Unpack both base and target OS images
    await this.context.get().os.fetch();
    await this.context.get().hupOs.fetch();
    // configure the image
    await this.context.get().os.configure()
    // Starts the registry
    await this.context.get().hup.runRegistry(this, this.context.get().hupOs.image.path);
  },
  tests: [
    "./tests/smoke",
    "./tests/rollback-health",
    "./tests/rollback-altboot",
    // "./tests/self-serve-dashboard",
  ],
};
