/*
 * Copyright 2021 balena
 *
 * @license Apache-2.0
 */

'use strict';

module.exports = {
  title: 'Smoke test',
  run: async function (test) {
    await this.context.get().hup.initDUT(
      this, test, this.context.get().link);

    const before = await this.context.get().hup.getOSVersion(
      this, this.context.get().link);
    test.comment(`VERSION (before): ${before}`);

    await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);

    test.comment(`Reducing amount of time needed for rollback-health to fail`)
    // reduce number of failures needed to trigger rollback
    await this.context.get().worker.executeCommandInHostOS(
      `sed -i -e "s/COUNT=.*/COUNT=1/g" -e "s/TIMEOUT=.*/TIMEOUT=10/g" $(find /mnt/sysroot/inactive/ | grep "bin/rollback-health")`,
      this.context.get().link,
    );

    await this.context.get().worker.rebootDut(this.context.get().link);

    const after = await this.context.get().hup.getOSVersion(
      this, this.context.get().link);
    test.comment(`VERSION (after): ${after}`);

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
        `[ -f /mnt/state/rollback-health-triggered ] && echo fail || echo pass`,
        this.context.get().link),
      "pass",
      "Rollback-health should succeed health checks.",
    );

    test.is(
      await this.context.get().worker.executeCommandInHostOS(
        `[ -f /mnt/state/rollback-health-failed ] && echo fail || echo pass`,
        this.context.get().link),
      "pass",
      "Rollback-health should succeed running previous hooks.",
    );

    test.comment(`Successful hostapp-update from ${before} to ${after}`);
  },
};
