/*
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

const request = require("request-promise");
const SUPERVISOR_PORT = 48484;
const fs = require('fs');

module.exports = {
	title: "Device Tree tests",
	tests: [
		{
			title: "DToverlay & DTparam tests",
			run: async function (test) {
				let ip = await this.context.get().worker.ip(this.context.get().link);

				// Wait for supervisor API to start
				await this.context.get().utils.waitUntil(async () => {
					return (
						(await request({
							method: "GET",
							uri: `http://${ip}:${SUPERVISOR_PORT}/ping`,
						})) === "OK"
					);
				}, false);

				const targetState = {
					"local": {
						"name": "local",
						"config": {
							"HOST_CONFIG_dtoverlay": "\"vc4-fkms-v3d\",\"i2c0\",\"i2c1\",\"i2c3\"",
							"HOST_CONFIG_dtparam": "\"i2c_arm=on\",\"spi=on\",\"audio=on\",\"foo=bar\",\"level=42\"",
							"SUPERVISOR_PERSISTENT_LOGGING": "true",
							"SUPERVISOR_LOCAL_MODE": "true"
						},
						"apps": {}
					},
					"dependent": {
						"apps": [],
						"devices": []
					}
				}

				await this.context
					.get()
					.worker.executeCommandInHostOS(
						'touch /tmp/reboot-check',
						this.context.get().link,
					);

				// Setting the device tree variables using Supervisor API
				// This request reboots the DUT
				const setTargetState = await request({
					method: "POST",
					headers: {
						'Content-Type': 'application/json',
					},
					json: true,
					body: targetState,
					uri: `http://${ip}:${SUPERVISOR_PORT}/v2/local/target-state`,
				});

				test.same(setTargetState, { status: "success", message: "OK" }, "DToverlay & DTparam configured successfully through Supervisor API");

				await this.context.get().utils.waitUntil(async () => {
					test.comment("Waiting for DUT to come back online after reboot...");
					return (
						(await this.context
							.get()
							.worker.executeCommandInHostOS(
								'[[ ! -f /tmp/reboot-check ]] && echo "pass"',
								this.context.get().link
							)) === "pass"
					);
				}, false);

				// IP of the device sometimes change after reboots, hence initalising again
				ip = await this.context.get().worker.ip(this.context.get().link);

				await this.context.get().utils.waitUntil(async () => {
					test.comment("Waiting for supervisor to be ready after reboot...");
					return (
						(await request({
							method: "GET",
							uri: `http://${ip}:${SUPERVISOR_PORT}/ping`,
						})) === "OK"
					);
				}, false);

				// Get the current target state of device
				const currentState = await request({
					method: "GET",
					uri: `http://${ip}:${SUPERVISOR_PORT}/v2/local/target-state`,
					json: true
				});

				test.equal(currentState.state.local.config.HOST_CONFIG_dtoverlay, targetState.local.config.HOST_CONFIG_dtoverlay, "DToverlay successfully set in target state")
				test.equal(currentState.state.local.config.HOST_CONFIG_dtparam, targetState.local.config.HOST_CONFIG_dtparam, "DTparam successfully set in target state")

				const dtoverlay = fs.readFileSync(`${__dirname}/dtoverlay.sh`).toString();
				const dtparam = fs.readFileSync(`${__dirname}/dtparam.sh`).toString();

				const overlayConfigTxt = await this.context
					.get()
					.worker.executeCommandInHostOS(
						`cd /tmp && ${dtoverlay}`,
						this.context.get().link
					);

				test.equal(overlayConfigTxt, targetState.local.config.HOST_CONFIG_dtoverlay, "DToverlay successfully configured in the config.txt")
				const paramConfigTxt = await this.context
					.get()
					.worker.executeCommandInHostOS(
						`cd /tmp && ${dtparam}`,
						this.context.get().link
					);
				test.equal(paramConfigTxt, targetState.local.config.HOST_CONFIG_dtparam, "DTparam successfully configured in the config.txt")
			},
		},
	],
};
