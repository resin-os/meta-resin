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

module.exports = {
  title: "Container healthcheck test",
  os: {
    type: "object",
    required: ["variant"],
    properties: {
      variant: {
        type: "string",
        const: "Development",
      },
    },
  },
  run: async function (test) {
    const ip = await this.context.get().worker.ip(this.context.get().link);

    const state = await this.context
      .get()
      .worker.pushContainerToDUT(ip, __dirname, "healthcheck");

    // wait until status of container is "healthy"
    await this.context.get().utils.waitUntil(async () => {
      test.comment("Waiting to container to report as healthy...");
      // retrieve healthcheck events
      let health = JSON.parse(await this.context
        .get()
        .worker.executeCommandInHostOS(
          `printf '["null"'; balena events --filter container=${state.services.healthcheck} --filter event=health_status --since 1 --until "$(date +%Y-%m-%dT%H:%M:%S.%NZ)" --format '{{json .}}' | while read LINE; do printf ",$LINE"; done; printf ']'`,
          ip
        )
      )
      let status = health.reduce(function (result, element) {
        if (element.status != null) {
          result.push(element.status);
        }
        return result;
      }, [])

      return status.includes("health_status: healthy")

    }, false);

    const out = await this.context
      .get()
      .worker.executeCommandInContainer("rm /tmp/health", "healthcheck", ip);

    let status = [];
    // Use waitUntil, because sometimes it takes time for the container to report as unhealthy, so we want to be able to re-check
    await this.context.get().utils.waitUntil(async () => {
      test.comment("Waiting to container to report as unhealthy...");
      // retrieve healthcheck events
      let events = JSON.parse(
        await this.context
          .get()
          .worker.executeCommandInHostOS(
            `printf '["null"'; balena events --filter container=${state.services.healthcheck} --filter event=health_status --since 1 --until "$(date +%Y-%m-%dT%H:%M:%S.%NZ)" --format '{{json .}}' | while read LINE; do printf ",$LINE"; done; printf ']'`,
            ip
          )
      );

      // extract "health status: X" and add to an array
      status = events.reduce(function (result, element) {
        if (element.status != null) {
          result.push(element.status);
        }
        return result;
      }, [])
      test.comment(`Container is currently: "${status[status.length - 1]}"`);

      return status.includes("health_status: unhealthy"); // Exit this block when container goes to "unhealthy"
    }, false);

    // check that the container went from healthy to unhealthy
    test.ok(
      (status.includes("health_status: unhealthy")),
      "Container should go from healthy to unhealthy"
    );
  },
};
