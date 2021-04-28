"use strict";

module.exports = {
  title: "Image preload test",
  run: async function (test) {
    // make sure DUT is online
    await this.context.get().utils.waitUntil(() => {
      return this.context
        .get()
        .cloud.balena.models.device.isOnline(this.context.get().balena.uuid);
    }, false);

    // wait until the service is running
    await this.context.get().cloud.waitUntilServicesRunning(
      this.context.get().balena.uuid, 
      [`main`], 
      this.context.get().balena.initialCommit
    )

    test.ok(true, `Preload commit hash should be ${this.context.get().balena.initialCommit}`);

    let downloadedLog = await this.context.get().cloud.checkLogsContain(
      this.context.get().balena.uuid, 
      `Downloading`, 
      `Supervisor starting`
    );

    test.ok(!downloadedLog, `Device should run application without downloading`);
  },
};
