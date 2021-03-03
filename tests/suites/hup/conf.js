/*
 * Copyright 2021 balena
 *
 * @license Apache-2.0
 */

'use strict';

// Device identification
function uid(a) {
	return a
		? (a ^ (Math.random() * 16)).toString(16)
		: ([1e15] + 1e15).replace(/[01]/g, uid);
}
// Test identification
const id = `${Math.random()
	.toString(36)
	.substring(2, 10)}`;

module.exports = options => {
	return {
		id,
		balena: {
			apiUrl: options.balenaApiUrl,
		},
		balenaOS: {
			config: {
				uuid: uid(),
				pubKey: options.osPubkey,
			},
			download: {
				type: options.downloadType,
				version: options.downloadVersion,
				source: options.downloadSource,
			},
			network: {
				wired: options.networkWired,
				wireless: options.networkWireless,
			},
		},
	};
};
