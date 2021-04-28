/* Copyright 2019 balena
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

"use strict";
const { exec } = require("mz/child_process");

const waitUntilServicesRunning = async(that, uuid, services, commit, test) => {
  await that.context.get().utils.waitUntil(async () => {
    test.comment(`Waiting for device: ${uuid} to run services: ${services} at commit: ${commit}`);
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
  title: "Multicontainer app tests",
  run: async function (test) {
    const moveApplicationName = `${
      this.context.get().balena.application
    }_MoveDevice`;

    // create new application
    await this.context.get().cloud.balena.models.application.create({
      name: moveApplicationName,
      deviceType: this.context.get().os.deviceType,
      organization: this.context.get().balena.organization,
    });

    this.context.set({
      moveApp: moveApplicationName,
    });

    this.suite.context.set({
      moveApp: moveApplicationName,
    });

    // Remove this app at the end of the test suite
    this.suite.teardown.register(() => {
      this.log(`Removing application ${moveApplicationName}`);
      return this.context
        .get()
        .cloud.balena.models.application.remove(moveApplicationName);
    });

    // push multicontainer app release to new app
    test.comment(`Cloning repo...`);
    await exec(
      `git clone https://github.com/balena-io-examples/multicontainer-getting-started.git ${__dirname}/app`
    );

    test.comment(`Pushing release...`);
    const initialCommit = await this.context.get().cloud.pushReleaseToApp(moveApplicationName, `${__dirname}/app`)
    this.suite.context.set({
      multicontainer: {
        initialCommit: initialCommit
      }
    })
  },
  tests: [
    {
      title: "Move device to multicontainer App",
      run: async function (test) {
        // move device to new app
        await this.context
          .get()
          .cloud.balena.models.device.move(
            this.context.get().balena.uuid,
            this.context.get().moveApp
          );

        await waitUntilServicesRunning(
          this,
          this.context.get().balena.uuid, 
          [`frontend`, `proxy`, `data`], 
          this.context.get().multicontainer.initialCommit,
          test
        )

        test.ok(true, "All services running");
      },
    },
    {
      title: "Set device environment variables",
      run: async function (test) {
        let key = "deviceVar";
        let value = "value";

        // set device variable
        await this.context
          .get()
          .cloud.balena.models.device.envVar.set(
            this.context.get().balena.uuid,
            key,
            value
          );

        // Check that device env variable is present in each service
        let services  = [`frontend`, `proxy`, `data`]
        await this.context.get().utils.waitUntil(async () => {
          let results = {}
          for (let service of services){
            let env = await this.context.get().cloud.executeCommandInContainer(`env`, service, this.context.get().balena.uuid)
            if (env.includes(`${key}=${value}\n`)){
              results[service] = true
            } else {
              results[service] = false
            }
          }
          return services.every((service) => {
            return results[service] === true
          })
        }, false, 30);

        test.ok(true, `Should see device env variable`);
      },
    },
    {
      title: "Set service environment variables",
      run: async function (test) {
        let key = "serviceVar";
        let value = "value";

        let services = await this.context
          .get()
          .cloud.balena.models.device.getWithServiceDetails(
            this.context.get().balena.uuid
          );

        // set device service variable for frontend service
        await this.context
          .get()
          .cloud.balena.models.device.serviceVar.set(
            this.context.get().balena.uuid,
            services.current_services.frontend[0].service_id,
            key,
            value
          );

        // Check to see if variable is present in front end service
        await this.context.get().utils.waitUntil(async () => {
          test.comment("Checking to see if variables are visible...");
          let env = await this.context.get().cloud.executeCommandInContainer(`env`, `frontend`, this.context.get().balena.uuid)

          return env.includes(`${key}=${value}\n`);
        }, false, 30);
        test.ok(true, `Should service env var in service it was set for`);
      },
    },
    {
      title: "Move device back to original app",
      run: async function (test) {
        // move device to new app
        await this.context
          .get()
          .cloud.balena.models.device.move(
            this.context.get().balena.uuid,
            this.context.get().balena.application
          );

        // get latest commit
        let commit = await this.context
        .get()
        .cloud.balena.models.application.get(
          this.context.get().balena.application
        )
        .get("commit");


        await waitUntilServicesRunning(
          this,
          this.context.get().balena.uuid, 
          [`main`], 
          commit,
          test
        )

        test.ok(
          true,
          `Device should have been moved back to original app, and be running its service`
        );
      },
    },
  ],
};
