#!/bin/sh
#
# Copyright 2020 Balena Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

. /usr/libexec/os-helpers-logging
. /usr/libexec/os-helpers-time

# Delay in seconds between poll attempts.
HTTPS_POLL_DELAY=1
# Remote server address.
HTTPS_SERVER=https://api.balena-cloud.com/connectivity-check
# Timeout for curl command in seconds.
# Note that curl does not apply this timeout to DNS lookups.
CURL_TIMEOUT=5
# Maximum number of poll attempts (must be at least 1).
MAX_HTTPS_POLLS=100
# Don't bother updating or reporting errors for small differences.
TIME_DIFF_THRESHOLD=2

# Poll HTTPS server for time string.
info "Starting HTTPS time synchronisation."

HTTPS_POLL_COUNTER=0

# In theory the potential maximum delay is given by:
#     (((HTTPS_POLL_DELAY + CURL_TIMEOUT) * MAX_HTTPS_POLLS) - HTTPS_POLL_DELAY) seconds.
# Using the above calculation with the default values gives a delay
# period of approximately 10 minutes.
# Note that this period can be extended as curl DNS lookup timeouts do
# not obey the -m (--max-time) parameter.

while [ true  ]; do
	SYS_TIME=$(get_system_time_as_timestamp)
	SERVER_TIME_STRING=$(curl -m$CURL_TIMEOUT -k -I -s "$HTTPS_SERVER" --stderr - | grep -i Date: | sed -e 's/[Dd]ate: //')
	if [ ! -z "$SERVER_TIME_STRING" ]; then
		SERVER_TIME=$(get_server_time_as_timestamp "$SERVER_TIME_STRING")
		TIME_DIFF=$(get_abs_time_diff_from_timestamps "$SYS_TIME" "$SERVER_TIME")
		if [ "$TIME_DIFF" -gt "$TIME_DIFF_THRESHOLD" ]; then
			if [ "$SYS_TIME" -lt "$SERVER_TIME" ]; then
				$(set_system_time_from_timestamp "$SERVER_TIME")
				info "Time synchronised via HTTPS."
				info "Old time: $(get_display_time_from_timestamp "$SYS_TIME")"
				info "New time: $(get_display_time_from_timestamp "$SERVER_TIME")"
				exit 0
			else
				info "System time is already synchronised."
				warn "HTTPS header time is in the past."
				warn "Server time: $(get_display_time_from_timestamp "$SERVER_TIME")"
				warn "System time: $(get_display_time_from_timestamp "$SYS_TIME")"
				exit 0
			fi
		else
			info "System time is already synchronised."
			exit 0
		fi
	fi
	HTTPS_POLL_COUNTER=$(expr $HTTPS_POLL_COUNTER + 1)
	if [ "$HTTPS_POLL_COUNTER" -ge "$MAX_HTTPS_POLLS" ]; then
		fail "HTTPS time synchronisation failed after $MAX_HTTPS_POLLS attempts."
	fi
	sleep $HTTPS_POLL_DELAY
done
