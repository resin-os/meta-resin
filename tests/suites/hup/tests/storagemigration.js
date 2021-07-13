/*
 * Copyright 2021 balena
 *
 * @license Apache-2.0
 */

'use strict';

const shouldMigrate = async (that, test) => {
  // check if both aufs and overlayfs are supported, otherwise skip
  if (await that.context.get().worker.executeCommandInHostOS(
      `balena info 2>/dev/null | grep -o -e aufs -e overlay2`,
      that.context.get().link,
    ) === "overlay2") {
    test.comment(`SKIP: Already using overlayfs, skipping migration test.`)
    return false;
  }
  if (await that.context.get().worker.executeCommandInHostOS(
      `grep -e overlay -e aufs /proc/filesystems >/dev/null && echo pass`,
      that.context.get().link,
    ) !== "pass") {
    test.comment(`SKIP: Both aufs and overlayfs have to be supported to run a migration.`)
    return false;
  }
  return true;
}

const archiveMigrationLogs = async (that, test) => {
  test.comment(`Archiving migration logs`);
  const migration = await that.context.get().worker.executeCommandInHostOS(
      `set -x; journalctl -u balena -t balenad | grep 'to overlay2' || true`,
      that.context.get().link);
  const migrationLogs = require("path").join(that.suite.options.tmpdir, `storage-migration.log`);
  require("fs").writeFileSync(migrationLogs, migration);
  await that.archiver.add(migrationLogs);
  require("fs").unlinkSync(migrationLogs);
}

const waitForRollbackHealth = async (that, test) => {
  test.comment(`Waiting for rollback-health...`);
  await that.context.get().utils.waitUntil(async () => {
    return (
      (await that.context.get().worker.executeCommandInHostOS(
        `systemctl status rollback-health.service`,
        that.context.get().link,
      )) !== 'active'
    );
  }, true);
}

module.exports = {
  title: 'Storage migration test',
  // deviceType: {}, // TODO
  tests: [
    {
      title: 'Successful migration',
      run: async function(test) {
        await this.context.get().hup.initDUT(
          this, test, this.context.get().link);

        if (!(await shouldMigrate(this, test))) {
          return; // SKIP
        }

        const oldOsVersion = await this.context.get().hup.getOSVersion(
          this, this.context.get().link);
        test.comment(`OS version before HUP: ${oldOsVersion}`);

        const containerIDs = await this.context.get().worker.executeCommandInHostOS(
            `balena ps --format '{{.ID}}' 2>/dev/null`,
            this.context.get().link);

        await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);
        await this.context.get().hup.doReboot(this, test, this.context.get().link);

        await waitForRollbackHealth(this, test);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
                `[ -d /mnt/data/docker/overlay2 ] && echo pass || echo fail`,
                this.context.get().link),
          "pass",
          "overlay2 storage root should exist"
        );

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
                `balena info 2>/dev/null | awk '/Storage.Driver/{print $3}'`,
                this.context.get().link),
          "overlay2",
          "balenaEngine should be configured with the overlay2 storage driver"
        );

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
            `balena ps --format '{{.ID}}' 2>/dev/null`,
            this.context.get().link),
          containerIDs,
          "balenaEngine should run the previously running of containers"
        );

        await archiveMigrationLogs(this, test);
        const diskSize = await this.context.get().worker.executeCommandInHostOS(
            `balena image ls --format '{{.Size}}' | awk 'BEGIN{t=0; k=1000;M=k*1000;G=M*1000;} /kB$/{sub("kB","");t+=($0*k);} /MB$/{sub("MB","");t+=($0*M);} /GB$/{sub("GB","");t+=($0*G);} END{print t}'`,
            this.context.get().link);
        test.comment(`Total image size on disk: ${diskSize}`);
        test.comment("Migration successful");

      }
    },
    {
      title: 'Successful migration and rollback-health triggered',
      run: async function(test) {
        await this.context.get().hup.initDUT(
          this, test, this.context.get().link);

        if (!(await shouldMigrate(this, test))) {
          return; // SKIP
        }

        test.comment(`Creating data to migrate`);
        await this.context.get().worker.executeCommandInHostOS(
            `balena pull balenalib/${this.suite.deviceType.slug}-debian:buster && balena run -d --name test balenalib/${this.suite.deviceType.slug}-debian:buster balena-idle`,
            this.context.get().link,
          );

        await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);

        // break the inactive partition (new os) by replacing the openvpn binary
        await this.context.get().worker.executeCommandInHostOS(
            `cp /bin/bash $(find /mnt/sysroot/inactive/ | grep "bin/openvpn")`,
            this.context.get().link,
          );
        // reduce number of failures needed to trigger rollback
        await this.context.get().worker.executeCommandInHostOS(
            `sed -i -e "s/COUNT=.*/COUNT=1/g" $(find /mnt/sysroot/inactive/ | grep "bin/rollback-health")`,
            this.context.get().link,
          );

        await this.context.get().hup.doReboot(this, test, this.context.get().link);
        await waitForRollbackHealth(this, test);

        // NOTE how much does this overlap with the rollback tests we have in
        // testlodge, implicitely I have to rely on that working as expected
        // here and if it breaks it would also break this test...
        test.is(
          await this.context.get().worker.executeCommandInHostOS(
            `[ -f /mnt/state/rollback-health-triggered ] || [ -f /mnt/state/rollback-health-failed ] && echo pass || echo fail`,
            this.context.get().link),
          "pass",
          "Rollback-health should fail",
        );

        // sleep 10s
        await new Promise(resolve => setTimeout(resolve, 11000));

        // FIXME how do we wait for the rollback triggered reboot?

        await that.context.get().utils.waitUntil(async () => {
          return (
            (await that.context.get().worker.executeCommandInHostOS(
              `systemctl status balena.service`,
              that.context.get().link,
            )) === 'active'
          );
        }, true);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
              `balena ps -a --format '{{.ID}}' | xargs balena inspect --format '{{.GraphDriver.Name}}'`,
              this.context.get().link)
            .split("\n")
            .reduce((accum, val) => accum && (val == "overlay2")),
          true,
          "All containers should be on overlay2",
        )

        await archiveMigrationLogs(this, test);
      }
    },
    {
      title: 'Failed migration dumps logs on state partition',
      run: async function(test) {
        await this.context.get().hup.initDUT(
          this, test, this.context.get().link);

        if (!(await shouldMigrate(this, test))) {
          return; // SKIP
        }

        await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);

        // make migration fail by messing up aufs storage root
        await this.context.get().worker.executeCommandInHostOS(
            `rm -rf /mnt/data/docker/aufs/diff`,
            this.context.get().link,
          );

        await this.context.get().hup.doReboot(this, test, this.context.get().link);
        await waitForRollbackHealth(this, test);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
                `[ -f /mnt/state/balena-engine-storage-migration.log ] && echo pass || echo fail`,
                this.context.get().link),
          "pass",
          "balenaEngine should dump migration logs on failure"
        );
      }
    },
    {
      title: 'Second engine boot cleans up aufs data',
      run: async function(test) {
        await this.context.get().hup.initDUT(
          this, test, this.context.get().link);

        if (!(await shouldMigrate(this, test))) {
          return; // SKIP
        }

        await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);
        await this.context.get().hup.doReboot(this, test, this.context.get().link);
        await waitForRollbackHealth(this, test);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
                `[ -d /mnt/data/docker/overlay2 ] && echo pass || echo fail`,
                this.context.get().link),
          "pass",
          "overlay2 storage root should exist"
        );

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
                `[ -d /mnt/data/docker/aufs ] && echo pass || echo fail`,
                this.context.get().link),
          "pass",
          "aufs storage root should exist"
        );

        test.comment(`Restarting engine`)
        await this.context.get().worker.executeCommandInHostOS(
              `systemctl restart balena`,
              this.context.get().link);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
                `[ ! -d /mnt/data/docker/aufs ] && echo pass || echo fail`,
                this.context.get().link),
          "pass",
          "aufs storage root should be cleaned up"
        );
      }
    },
  ]
};
