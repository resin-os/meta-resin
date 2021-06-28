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

const URL_TEST = "www.google.com";

module.exports = {
  title: "Connectivity tests",
  tests: [
    {
      title: "Interface tests",
      tests: ["wired", "wireless"].map((adaptor) => {
        return {
          title: `${adaptor.charAt(0).toUpperCase()}${adaptor.slice(1)} test`,
          os: {
            type: "object",
            required: ["network"],
            properties: {
              network: {
                type: "object",
                required: [adaptor],
                properties: {
                  [adaptor]: {
                    type: "boolean",
                    const: true,
                  },
                },
              },
            },
          },
          run: async function (test) {
            let testIface = (adaptor === "wireless") ? "wifi" : "ethernet";
            const iface = await this.context
              .get()
              .worker.executeCommandInHostOS(
                `nmcli d  | grep ' ${testIface} ' | grep connected | awk '{print $1}'`,
                this.context.get().link
              );

            if (iface === "") {
              throw new Error(`No ${testIface} interface found.`);
            }

            let ping = await this.context
              .get()
              .worker.executeCommandInHostOS(
                `ping -c 10 -I ${iface} ${URL_TEST}`,
                this.context.get().link
              );

            test.ok(ping.includes("10 packets transmitted, 10 packets received"), `${URL_TEST} responded over ${testIface}`);
          },
        };
      }),
    },
    {
      title: "Proxy tests",
      tests: ["redsocks", "http-connect"].map((proxy) => {
        return {
          title: `${proxy.charAt(0).toUpperCase()}${proxy.slice(1)} test`,
          run: async function (test) {
            const PROXY_PORT = 8123;

            await this.context
              .get()
              .worker.executeCommandInHostOS(
                "mkdir -p /mnt/boot/system-proxy",
                this.context.get().link
              );

            const proxyState = await this.context.get().worker.proxy({
              port: PROXY_PORT,
            });

            await this.context
              .get()
              .worker.executeCommandInHostOS(
                'printf "' +
                  "base { \n" +
                  "log_debug = off; \n" +
                  "log_info = on; \n" +
                  "log = stderr; \n" +
                  "daemon = off; \n" +
                  "redirector = iptables; \n" +
                  "} \n" +
                  "redsocks { \n" +
                  `type = ${proxy}; \n` +
                  `ip = ${proxyState.ip}; \n` +
                  `port = ${PROXY_PORT}; \n` +
                  "local_ip = 127.0.0.1; \n" +
                  "local_port = 12345; \n" +
                  '} \n" > /mnt/boot/system-proxy/redsocks.conf',
                this.context.get().link
              );

            // Rebooting the DUT
            await this.context.get().worker.rebootDut(this.context.get().link)

            await this.context
              .get()
              .worker.executeCommandInHostOS(
                `ping -c 10 ${URL_TEST}`,
                this.context.get().link
              );
            test.true(`${URL_TEST} responded over ${proxy} proxy`);

            await this.context
              .get()
              .worker.executeCommandInHostOS(
                "rm -rf /mnt/boot/system-proxy",
                this.context.get().link
              );

            // Rebooting the DUT
            await this.context.get().worker.rebootDut(this.context.get().link)
          },
        };
      }),
    },
  ],
};
