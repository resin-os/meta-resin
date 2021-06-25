/*
 * Copyright 2021 balena
 *
 * @license Apache-2.0
 */

'use strict';

module.exports = {
  title: 'Rollback health tests',
  tests: [
    {
      title: 'Broken balena-engine',
      run: async function(test) {
        await this.context.get().hup.initDUT(
          this, test, this.context.get().link);

        await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);

        // reduce number of failures needed to trigger rollback
        await this.context.get().worker.executeCommandInHostOS(
          `sed -i -e "s/COUNT=.*/COUNT=1/g" -e "s/TIMEOUT=.*/TIMEOUT=10/g" $(find /mnt/sysroot/inactive/ | grep "bin/rollback-health")`,
          this.context.get().link,
        );

        // break balena-engine
        await this.context.get().worker.executeCommandInHostOS(
          `cp /bin/bash $(find /mnt/sysroot/inactive/ | grep "usr/bin/balena-engine")`,
          this.context.get().link,
        );

        await this.context.get().worker.rebootDut(this.context.get().link);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
            `[ -f /mnt/state/rollback-health-breadcrumb ] && echo pass || echo fail`,
            this.context.get().link),
          "pass",
          "There should be a breadcrumb file in the state partition",
        );

        test.comment(`Waiting for rollback-health...`);
        await this.context.get().utils.waitUntil(async () => {
          return (
            (await this.context.get().worker.executeCommandInHostOS(
              `systemctl status rollback-health.service`,
              this.context.get().link,
            )) !== 'active'
          );
        }, true);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
            `[ -f /mnt/state/rollback-health-triggered ] && echo pass || echo fail`,
            this.context.get().link),
          "pass",
          "There should be a flag file in the state partition",
        );
      },
    },
    {
      title: 'Broken VPN',
      run: async function(test) {
        await this.context.get().hup.initDUT(
          this, test, this.context.get().link);

        await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);

        // reduce number of failures needed to trigger rollback
        await this.context.get().worker.executeCommandInHostOS(
          `sed -i -e "s/COUNT=.*/COUNT=1/g" -e "s/TIMEOUT=.*/TIMEOUT=10/g" $(find /mnt/sysroot/inactive/ | grep "bin/rollback-health")`,
          this.context.get().link,
        );

        // break openvpn
        await this.context.get().worker.executeCommandInHostOS(
          `cp /bin/bash $(find /mnt/sysroot/inactive/ | grep "bin/openvpn")`,
          this.context.get().link,
        );

        await this.context.get().worker.rebootDut(this.context.get().link);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
            `[ -f /mnt/state/rollback-health-breadcrumb ] && echo pass || echo fail`,
            this.context.get().link),
          "pass",
          "There should be a breadcrumb file in the state partition",
        );

        test.comment(`Waiting for rollback-health`);
        await this.context.get().utils.waitUntil(async () => {
          return (
            (await this.context.get().worker.executeCommandInHostOS(
              `systemctl status rollback-health.service`,
              this.context.get().link,
            )) !== 'active'
          );
        }, true);

        test.is(
          await this.context.get().worker.executeCommandInHostOS(
            `[ -f /mnt/state/rollback-health-triggered ] && echo pass || echo fail`,
            this.context.get().link),
          "pass",
          "There should be a flag file in the state partition",
        );
      },
    },
  ]
};
