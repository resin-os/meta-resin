const Bluebird = require("bluebird");
const exec = Bluebird.promisify(require("child_process").exec);

module.exports = {
  title: "Bluetooth tests",
  deviceType: {
    type: "object",
    required: ["data"],
    properties: {
      data: {
        type: "object",
        required: ["connectivity"],
        properties: {
          connectivity: {
            type: "object",
            required: ["bluetooth"],
            properties: {
              bluetooth: {
                type: "boolean",
                const: true,
              },
            },
          },
        },
      },
    },
  },
  tests: [
    {
      title: "Bluetooth scanning test",
      run: async function (test) {
        // get the testbot bluetooth name
        let btName = await exec("bluetoothctl show | grep Name");
        let btNameParsed = /(.*): (.*)/.exec(btName); // the bluetoothctl command returns "Name: <btname>", so extract the <btname here>

        // make testbot bluetooth discoverable
        await exec("bluetoothctl discoverable on");

        // scan for bluetooth devices on DUT, we retry a couple of times
        let scan = "";
        await this.context.get().utils.waitUntil(async () => {
          test.comment("Scanning for bluetooth devices...");
          scan = await this.context
            .get()
            .worker.executeCommandInHostOS(
              "hcitool scan",
              this.context.get().link
            );
          return scan.includes(btNameParsed[2]);
        });

        test.is(
          scan.includes(btNameParsed[2]),
          true,
          "DUT should be able to see testbot when scanning for bluetooth devices"
        );
      },
    },
  ],
};
