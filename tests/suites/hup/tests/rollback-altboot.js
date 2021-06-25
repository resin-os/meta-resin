/*
 * Copyright 2021 balena
 *
 * @license Apache-2.0
 */

'use strict';

module.exports = {
  title: 'Rollback altboot (broken init) test',
  run: async function(test) {
    await this.context.get().hup.initDUT(
      this, test, this.context.get().link);

    await this.context.get().hup.doHUP(this, test, 'image', this.context.get().hup.payload, this.context.get().link);

    // break init
    await this.context.get().worker.executeCommandInHostOS(
      `rm /mnt/sysroot/inactive/current/boot/init`,
      this.context.get().link,
    );

    await this.context.get().worker.rebootDut(this.context.get().link);

    test.is(
      await this.context.get().worker.executeCommandInHostOS(
        `[ -f /mnt/state/rollback-altboot-breadcrumb ] && echo pass || echo fail`,
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
        `[ -f /mnt/state/rollback-altboot-triggered ] && echo pass || echo fail`,
        this.context.get().link),
      "pass",
      "There should be a flag file in the state partition",
    );
  },
};
