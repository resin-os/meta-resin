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

const fsPromises = require('fs').promises;
const CONFIG_FILE = `${__dirname}/modems.json`;
const { delay } = require("bluebird");

module.exports = {
    title: "Cellular tests",
    tests: ((typeof process.env.MODEMS === "string") ? JSON.parse(process.env.MODEMS) : []).map((modem_type) => {
        return {
            title: `Modem test - ${modem_type}`,
            run: async function (test) {
                test.comment("Starting Modem Tests...")

                async function getConfig() {
                    const data = await fsPromises.readFile(CONFIG_FILE)
                        .catch((err) => console.error('Failed to read config file', err));

                    return JSON.parse(data.toString());
                }   

                // check that we support the provided modem
                const config = await getConfig();

                test.is(
                    config.modems.includes(modem_type),
                    true,
                    `Check if ${modem_type} is a supported modem.`
                )

                // scan for modems that are attached to the device
                await this.context.get().utils.waitUntil(async () => {
                    test.comment(`Scanning for modems...`)
                    let modems = await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli --scan-modems && mmcli --list-modems`,
                        this.context.get().link,
                    );
                    return (!modems.includes("No modems were found"))
                });

                // list modems and extract hardware iden
                let modemStore = (await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli --list-modems | awk '{printf "%s ",$NF}' | sed 's/ *$//g'`,
                        this.context.get().link,
                    )
                ).split(" ");

                test.is(
                    modemStore.includes(modem_type),
                    true,
                    `Check if DUT has a ${modem_type} modem.`
                )

                let dbusAddress = JSON.parse(await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli --list-modems -J | jq '."modem-list"'`,
                        this.context.get().link,
                    )
                )

                const promises = await dbusAddress.map(async (address) => {
                    let hw = await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli -m ${address} -J | jq '.modem.generic.model' -r`,
                        this.context.get().link,
                    )
                    return {addr: address, hardware: hw}
                })

                const hwMap = await Promise.all(promises)
                const hwMatch = hwMap.find((mapping) =>  mapping.hardware === modem_type)
                let targetAddress = hwMatch.addr;
                
                // enable modem
                await this.context
                .get()
                .worker.executeCommandInHostOS(
                    `mmcli --modem=${targetAddress} --enable`,
                    this.context.get().link,
                )

                // set parameters
                await this.context
                .get()
                .worker.executeCommandInHostOS(
                    `mmcli -m ${targetAddress} --simple-connect='apn=${config.network.apn},ip-type=${config.network.ipType}'`,
                    this.context.get().link,
                )

                // check to see if modem is connected
                let modemData = JSON.parse(await this.context
                .get()
                .worker.executeCommandInHostOS(
                    `mmcli -m ${targetAddress} -J`,
                    this.context.get().link,
                ))

                test.is(
                    modemData.modem.generic.state,
                    "connected",
                    "Check modem is connected to network."
                )
                
                const promisesBearer = await modemData.modem.generic.bearers.map(async (bearer) => {
                    let connected = await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli -m ${targetAddress} -b ${bearer} -J | jq '.bearer.status.connected' -r`,
                        this.context.get().link,
                    )
                    return {bear: bearer, conn: connected}
                }
                )

                const bearerResolve = await Promise.all(promisesBearer)            
                const bearerMatch = bearerResolve.find((mapping) =>  mapping.conn === "yes")
                let targetBearer = bearerMatch.bear;

                let ipAddress = await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli -m ${targetAddress} -b ${targetBearer} -J | jq '.bearer."ipv4-config".address' -r`,
                        this.context.get().link,
                    )

                let iface = await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli -m ${targetAddress} -b ${targetBearer} -J | jq '.bearer.status.interface' -r`,
                        this.context.get().link,
                    )

                await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli --modem=${targetAddress} --bearer=${targetBearer}`,
                        this.context.get().link,
                    )
                
                await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `ip link set ${iface} up`,
                        this.context.get().link,
                    )

                await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `ip addr add ${ipAddress}/32 dev ${iface}`,
                        this.context.get().link,
                    )

                await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `ip link set dev ${iface} arp off`,
                        this.context.get().link,
                    )

                await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `ip route add default dev ${iface} metric 200`,
                        this.context.get().link,
                    )

                let ping = await this.context
                .get()
                .worker.executeCommandInHostOS(
                    `ping -4 -c 10 -I ${iface} ${config.network.testUrl}`,
                    this.context.get().link
                );

                test.ok(ping.includes("10 packets transmitted, 10 packets received"), `ip address ${config.network.testUrl} should respond over ${iface}`);     

            
                test.teardown(async () => {
                    test.comment("Disconnecting the modem")
                    await this.context
                    .get()
                    .worker.executeCommandInHostOS(
                        `mmcli -m ${targetAddress} --simple-disconnect && mmcli -m ${targetAddress} --disable`,
                        this.context.get().link
                    )
                })
            },
        };
    }),
};
