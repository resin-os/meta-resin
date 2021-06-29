/*
 * Copyright 2018 balena
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

// Test identification
const id = `${Math.random().toString(36).substring(2, 10)}`;

module.exports = (options) => {
  return {
    id,
    balenaOS: {
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
    balena: {
      application: {
        env: {
          delta: options.supervisorDelta || false,
        },
      },
      apiKey: options.balenaApiKey,
      apiUrl: options.balenaApiUrl,
      organization: options.organization
    },
  };
};
