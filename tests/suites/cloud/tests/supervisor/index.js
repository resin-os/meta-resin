`use strict`;
const { exec } = require("mz/child_process");

const waitUntilServicesRunning = async(that, uuid, services, commit, test) => {
  test.comment(`Waiting for device: ${uuid} to run services: ${services} at commit: ${commit}`);
  await that.context.get().utils.waitUntil(async () => {
    let deviceServices = await that.context.get().cloud.balena.models.device.getWithServiceDetails(
      uuid
      );
    let running = false
    running = services.every((service) => {
      return (deviceServices.current_services[service][0].status === "Running") && (deviceServices.current_services[service][0].commit === commit)
    })
    return running;
  }, false, 50)
}

module.exports = {
  title: "Supervisor test suite",
  tests: [
    {
      title: "Provisioning without deltas",
      run: async function (test) {
        test.comment(`Disabling deltas`);
        await this.context
          .get()
          .cloud.balena.models.device.configVar.set(
            this.context.get().balena.uuid,
            "BALENA_SUPERVISOR_DELTA",
            0
          );
        
        // add a comment to the end of the server.js file, to trigger a delta when pushing
        await exec(`echo "//comment" >> ${this.context.get().appPath}/server.js`);
        test.comment(`Pushing release...`);

        let secondCommit = await this.context.get().cloud.pushReleaseToApp(
          this.context.get().balena.application, 
          `${this.context.get().appPath}`
        );

        await waitUntilServicesRunning(
          this,
          this.context.get().balena.uuid, 
          [`main`], 
          secondCommit,
          test
        )

        // device should have downloaded application without mentioning that deltas are being used
        let usedDeltas = await this.context.get().cloud.checkLogsContain(
          this.context.get().balena.uuid, 
          `Downloading delta for image`, 
          `Applied configuration change {"SUPERVISOR_DELTA":"0"}`
        );

        test.is(
          !usedDeltas,
          true,
          `Device shouldn't use deltas to download new release`
        );
        
        // re-enable deltas to save time later
        await this.context
        .get()
        .cloud.balena.models.device.configVar.set(
          this.context.get().balena.uuid,
          "BALENA_SUPERVISOR_DELTA",
          1
        );
      },
    },
    {
      title: "Supervisor reload test",
      run: async function (test) {
        let supervisorVersion = await this.context.get().cloud.getSupervisorVersion(this.context.get().balena.uuid)
        test.comment(`Supervisor version ${supervisorVersion} detected`);

        // remove supervisor container
        test.comment(`removing supervisor`);
        await this.context
          .get()
          .cloud.executeCommandInHostOS(
            `systemctl stop balena-supervisor && balena rm balena_supervisor && balena rmi -f $(balena images | grep supervisor | awk '{print $3}')`,
            this.context.get().balena.uuid
          );

        // run supervisor update script
        test.comment(`running update supervisor script...`);
        let updateLog = await this.context
          .get()
          .cloud.executeCommandInHostOS(
            `update-balena-supervisor`,
            this.context.get().balena.uuid
          );

        test.comment(updateLog)

        let updatedSupervisorVersion = "";
        await this.context.get().utils.waitUntil(async () => {
          test.comment(`checking supervisor has been re-downloaded...`);
         
          updatedSupervisorVersion = await this.context.get().cloud.getSupervisorVersion(this.context.get().balena.uuid)
          test.comment(`Detected version: ${updatedSupervisorVersion}`)
          return updatedSupervisorVersion === supervisorVersion
        }, false, 50);

        test.is(
          supervisorVersion,
          updatedSupervisorVersion,
          `Supervisor should have same version that it started with`
        );

        // balena ps shows balena_supervisor running
        test.comment(`checking supervisor is running again...`);
        let supervisorRunning = await this.context
          .get()
          .cloud.executeCommandInHostOS(
            `balena ps | grep supervisor`,
            this.context.get().balena.uuid
          );

        test.is(
          supervisorRunning !== "",
          true,
          `Supervisor should now be running`
        );
      },
    },
    {
      title: "Override lock test",
      run: async function (test) {
        let firstCommit = await this.context.get().cloud.balena.models.application.get(
          this.context.get().balena.application
        ).get("commit");

        // create a lockfile
        let createLockfile = await this.context.get().cloud.executeCommandInContainer(
          `bash -c '(flock -x -n 200)200>/tmp/balena/updates.lock'`, 
          `main`,
          this.context.get().balena.uuid)

        // push release to application
        await exec(`echo "//comment" >> ${this.context.get().appPath}/server.js`);
        test.comment(`Pushing release...`);
        let secondCommit = await this.context.get().cloud.pushReleaseToApp(
          this.context.get().balena.application, 
          `${this.context.get().appPath}` // push original release to application (node hello world)
        );

        // check original application is downloaded - shouldn't be installed
        await this.context.get().utils.waitUntil(async () => {
          test.comment(
            "Checking if release is downloaded, but not installed..."
          );
          let services = await this.context
            .get()
            .cloud.balena.models.device.getWithServiceDetails(
              this.context.get().balena.uuid
            );
          let downloaded = false;
          let originalRunning = false;
          services.current_services.main.forEach((service) => {
            if (
              service.commit === secondCommit &&
              service.status === "Downloaded"
            ) {
              downloaded = true;
            }

            if (
              service.commit === firstCommit &&
              service.status === "Running"
            ) {
              originalRunning = true;
            }
          });
          return downloaded && originalRunning;
        }, false, 50);

        test.ok(
          true,
          `Release should be downloaded, but not running due to lockfile`
        );


        let updatesLocked = await this.context.get().cloud.checkLogsContain(
          this.context.get().balena.uuid, 
          `Updates are locked, retrying in 2s...`,           
        );

        test.ok(updatesLocked, `Update lock message should appear in logs`)

        // enable lock override
        await this.context
          .get()
          .cloud.balena.models.device.configVar.set(
            this.context.get().balena.uuid,
            "BALENA_SUPERVISOR_OVERRIDE_LOCK",
            1
          );

        await waitUntilServicesRunning(
          this,
          this.context.get().balena.uuid, 
          [`main`], 
          secondCommit,
          test
        )

        test.ok(
          true,
          `Second release should now be running, as override lock was enabled`
        );

        // remove lockfile
        let removeLockfile = await this.context.get().cloud.executeCommandInContainer(
          `rm /tmp/balena/updates.lock`, 
          `main`,
          this.context.get().balena.uuid)
      },
    },
  ],
};
