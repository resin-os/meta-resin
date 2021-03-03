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
const imagefs = require('balena-image-fs');
const Docker = require('dockerode');
const retry = require('bluebird-retry');
const exec = require('bluebird').promisify(require('child_process').exec);

const fetchOS = async (that, version) => {
    if (version === "latest") {
      // make sure we always flash the development variant of the latest
      // OS release
      const versions = await that.context.get().sdk.balena.models.os.getSupportedVersions(
          that.suite.deviceType.slug,
        );
      version = versions.latest.replace('prod', 'dev');
    }

    const path = join(that.suite.options.tmpdir, `base_${version}.img`)

    let attempt = 0;
    const dlOp = async () => {
      attempt++;
      that.log(`Fetching balenaOS version ${version}, attempt ${attempt}...`);

      // TODO take version into account for caching...
      // how does this work for `latest`?
      if (await fse.pathExists(path)) {
        that.log(`[Cached used]`);
        return path;
      }

      // TODO progress
      const stream = await that.context.get().sdk.getDownloadStream(
          that.suite.deviceType.slug,
          version,
        );
      await new Promise((resolve, reject) => {
        stream.pipe(fs.createWriteStream(path))
          .on("finish", resolve)
          .on("error", reject);
        });

      return path
    };

    that.suite.teardown.register(async () => {
        console.log("Base image teardown");
        fse.unlinkSync(path);
      });

    return retry(dlOp, { max_retries: 3, interval: 500 });
};

// configureOS
// FIXME all of this can go once https://github.com/balena-os/leviathan/pull/433
// becomes available
const injectBalenaConfiguration = (image, configuration) => {
  // taken from: https://github.com/balena-io/leviathan/blob/master/core/lib/components/os/balenaos.js#L31
  return imagefs.interact(image, 1, async (fs) => {
    return require("util").promisify(fs.writeFile)("/config.json",
      JSON.stringify(configuration));
  });
};
const injectNetworkConfiguration = async (image, configuration) => {
  // taken from: https://github.com/balena-io/leviathan/blob/master/core/lib/components/os/balenaos.js#L43
  if (configuration.wireless == null) {
    return;
  }
  if (configuration.wireless.ssid == null) {
    throw new Error(
      `Invalide wireless configuration: ${configuration.wireless}`,
    );
  }

  const wifiConfiguration = [
    '[connection]',
    'id=balena-wifi',
    'type=wifi',
    '[wifi]',
    'hidden=true',
    'mode=infrastructure',
    `ssid=${configuration.wireless.ssid}`,
    '[ipv4]',
    'method=auto',
    '[ipv6]',
    'addr-gen-mode=stable-privacy',
    'method=auto',
  ];

  if (configuration.wireless.psk) {
    Reflect.apply(wifiConfiguration.push, wifiConfiguration, [
      '[wifi-security]',
      'auth-alg=open',
      'key-mgmt=wpa-psk',
      `psk=${configuration.wireless.psk}`,
    ]);
  }

  await imagefs.interact(image, 1, async (fs) => {
    return require("util").promisify(fs.writeFile)("/system-connections/balena-wifi",
      wifiConfiguration.join('\n'));
  });
};
const configureOS = async (that, imagePath, network, configJson) => {
  that.log(`Configuring base image`);
  await injectBalenaConfiguration(imagePath, configJson);
  await injectNetworkConfiguration(imagePath, network);
};

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
  // TODO should this be a common func?
  const testbotIP = (await exec(`ip addr | awk '/inet.*wlan0/{print $2}' | cut -d\/ -f1`)).trim();
  const hostappRef = `${testbotIP}:5000/hostapp@${digest}`;
  that.log(`Registry upload complete: ${hostappRef}`);

  that.suite.context.set({
    hup: {
      payload: hostappRef,
    }
  })
}

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
      // TODO do we need to print the output here?
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

const doReboot = async (that, test, target) => {
  test.comment(`Rebooting DUT`);
  await that.context.get().worker.executeCommandInHostOS(
    `touch /tmp/reboot-check && systemd-run --on-active=2 reboot`,
    target,
  );
  await that.context.get().utils.waitUntil(async () => {
    return (
      (await that.context.get().worker.executeCommandInHostOS(
        '[[ ! -f /tmp/reboot-check ]] && echo pass || echo fail',
        target,
      )) === 'pass'
    );
  }, true);
  test.comment(`DUT is back`);
};

const getOSVersion = async (that, target) => {
  // maybe https://github.com/balena-io/leviathan/blob/master/core/lib/components/balena/sdk.js#L210
  // will do? that one works entirely on the device though...
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
  await that.context.get().worker.flash(that.context.get().hup.baseOsImage);
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
    await that.context.get().hup.archiveLogs(this,
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

    // Network definitions {{{
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
    // }}}

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
          },
        },
        this.getLogger()
      ),

      hup: {
        doHUP:        doHUP,
        doReboot:     doReboot,
        fetchOS:      fetchOS,
        configureOS:  configureOS,
        getOSVersion: getOSVersion,
        initDUT:      initDUT,
        runRegistry:  runRegistry,
        archiveLogs:  archiveLogs,
      },
    });

    this.suite.teardown.register(() => {
      this.log("Worker teardown");
      return this.context.get().worker.teardown();
    });

    this.log("Setting up worker");
    await this.context
      .get()
      .worker.network(this.suite.options.balenaOS.network);

    // Unpack target OS image .gz
    await this.context.get().os.fetch({
      type: this.suite.options.balenaOS.download.type,
      version: this.suite.options.balenaOS.download.version,
      releaseInfo: this.suite.options.balenaOS.releaseInfo,
    });

    const path = await this.context.get().hup.fetchOS(
      this,
      this.suite.options.balenaOS.download.version,
    );
    await this.context.get().hup.configureOS(
      this,
      path,
      this.suite.options.balenaOS.network,
      this.context.get().os.configJson,
    );
    this.suite.context.set({
      hup: {
        baseOsImage: path
      }
    });

    await this.context.get().hup.runRegistry(this, this.context.get().os.image.path);
  },
  tests: [
    "./tests/smoke",
    // "./tests/self-serve-dashboard",
    // "./tests/rollback-altboot",
    // "./tests/rollback-health",
  ],
};
