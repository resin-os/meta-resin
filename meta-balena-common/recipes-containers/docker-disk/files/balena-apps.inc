#!/bin/bash

set -x

CURL="curl -s"

TRANSLATION=${TRANSLATION:-"v6"}

. /balena-api.inc

DEBUG=0

__dlog() {
	if [ "${DEBUG}" = "1" ]; then
		>&2 echo "${1}"
	fi
}

# Get release commit ID from public application name for a specific release
# Arguments:
#
# $1: Application name
# $2: Release version label
# $3: Balena API environment
#
# Result:
# Prints the release database ID in stdout
fetch_commitID_from_app() {
	local _appName="${1}"
	local _version="${2}"
	local _apiEnv="${3}"
	local _commitID=""

	__dlog "[fetch_commitID_from_app] Fetching images from ${_appName}, release ${_version}"

	# Fetch release commitID from application with specified version tag
	_commitID=$(balena_api_fetch_release_json "${_appName}" "${_apiEnv}" "${_version}" | jq --raw-output '.d[0].commit')
	echo "${_commitID}"
}

imageid_from_digest() {
	local _image="$1"
	local _digest
	local _image_name
	local _imageid
	local _digest_check
	_image_name=$(echo "${_image}" | cut -d "@" -f1)
	_digest=$(echo "${_image}" | cut -d "@" -f2)
	_imageid=$(docker images --filter=reference="${_image_name}" --format "{{.ID}}")
	_digest_check=$(docker images --digests --filter=reference="${_image_name}" --format "{{.Digest}}")
	if [ "${_digest}" = "${_digest_check}" ]; then
		echo "${_imageid}"
	fi
}

install_image() {
	local _serviceName="$1"
	local _image_location="${2}"
	local _version="${3}"
	local _image_class="${4}"
	local _image_store="${5}"
	local _image_reboot="${6}"
	local _app_uuid="${7}"
	local _app_id="${8}"
	local _image_id

	if [ "${_image_store}" = "data" ]; then
		>&2 docker pull --platform "${HOSTAPP_PLATFORM}" "${_image_location}"
		_image_id=$(imageid_from_digest "${_image_location}")
		if [ -z "${_image_id}" ]; then
			echo "[ERROR] No image id found"
			return
		fi
		# Convert OS versions to docker compatible tags
		_version="${_version/[^a-z0-9A-Z_.-]/_}"
		>&2 docker tag "${_image_id}" "${_serviceName}":"${_version}"

		if [ "${_image_class}" = "overlay" ]; then
			>&2 docker create --name "${_serviceName}" --label "${BALENA_HOSTOS_BLOCK_CLASS}=${_image_class}" \
				--label "${BALENA_HOSTOS_BLOCK_STORE}=${_image_store}" --label "${BALENA_HOSTOS_BLOCK_REQUIRES_REBOOT}=${_image_reboot}" \
				--label "${BALENA_HOSTOS_APP_UUID}=${_app_uuid}" --label "${BALENA_HOSTOS_APP_ID}=${_app_id}" --label "${BALENA_HOSTOS_RELEASE_VERSION}=${_version}" --label "${BALENA_HOSTOS_SERVICE_NAME}=${_serviceName}" \
				"${_image_location}" none
		fi
	fi
}

update_hostos_service() {
	local _json="$1"
	local _index="$2"
	local _serviceName="$3"
	local _version="$4"
	local _appUUID="$5"
	local _appID="$6"

	local _apps_json
	local _image_location
	local _svcID
	local _imageId
	local _image_class
	local _image_store
	local _image_requires_reboot

	_apps_json="${DATA_VOLUME}/apps.json"

	_svcID=$(echo "${_json}" | jq --raw-output ".d[${_index}].is_a_build_of__service.__id")
	_imageId=$(echo "${_json}" | jq --raw-output ".d[${_index}].is_part_of__release[0].image.__id")
	_labels=$(echo "${_json}" | jq --raw-output ".d[${_index}].is_part_of__release[0].release[0].composition.services.\"${_serviceName}\".labels")
	_image_location=$(echo "${_json}" | jq --raw-output ".d[${_index}].is_stored_at__image_location")
	_imageDigest=$(echo "${_json}" | jq  --raw-output ".d[${_index}].content_hash")

	while read -r -d '' entry_json_app<<-EOF
{
        "${_svcID}": {
            "serviceName": "${_serviceName}",
            "image": "${_image_location}@${_imageDigest}",
            "imageId": ${_imageId},
            "environment": {},
            "labels": ${_labels}
        }
}
EOF
	do
		# This avoid read returning error from not finding a newline termination
		:
	done

	_image_class=$(echo "${_labels}" | jq --raw-output ".\"${BALENA_HOSTOS_BLOCK_CLASS}\"")
	if [ -z "${_image_class}" ] || [ "${_image_class}" = "null" ]; then
		# Defaults to service
		_image_class="service"
	fi
	_image_store=$(echo "${_labels}" | jq --raw-output ".\"${BALENA_HOSTOS_BLOCK_STORE}\"")
	if [ -z "${_image_store}" ] || [ "${_image_store}" = "null" ]; then
		# Defaults to data
		_image_store="data"
	fi
	_image_requires_reboot=$(echo "${_labels}" | jq --raw-output ".\"${BALENA_HOSTOS_BLOCK_REQUIRES_REBOOT}\"")
	if [ -z "${_image_requires_reboot}" ] || [ "${_image_requires_reboot}" = "null" ]; then
		# Defaults to no
		_image_requires_reboot="no"
	fi
	install_image "${_serviceName}" "${_image_location}@${_imageDigest}" "${_version}" "${_image_class}" "${_image_store}" "${_image_requires_reboot}" "${_appUUID}" "${_appID}"
	echo "${entry_json_app}" | jq .
}

calculate_image_sizes() {
	local _json="$1"
	local _serviceNames
	local _image_size=0
	local _image_sizes=0
	local _index=0

	_serviceNames=$(echo "${_json}" | jq --raw-output '.d[0].is_part_of__release[0].release[0].composition.services | keys | @tsv' | tr "\t" " ")
	for _serviceName in ${_serviceNames}; do
		_image_size=$(echo "${_json}" | jq  --raw-output ".d[${_index}].image_size")
		_image_sizes=$((_image_sizes+_image_size))
		_index=$((_index+1))
	done
	echo "${_image_sizes}"
}

# Updates a apps.json file with a new preloaded app
# Arguments:
#
# $1: Application name
# $2: Release version
#
# Result:
# Updated apps.json in $DATA_VOLUME and the app json as output for further processing
update_hostos_services() {
	local _json="$1"
	local _version="$2"
	local _appUUID="$3"
	local _appID="$4"
	local _serviceNames
	local _index=0
	local _services_json="{}"
	local _service_json=""

	_serviceNames=$(echo "${_json}" | jq --raw-output '.d[0].is_part_of__release[0].release[0].composition.services | keys | @tsv' | tr "\t" " ")
	for _serviceName in ${_serviceNames}; do
		_service_json=$(update_hostos_service "${_json}" "${_index}" "${_serviceName}" "${_version}" "${_appUUID}" "${_appID}")
		_services_json=$(echo "${_services_json}" | jq ". += ${_service_json}")
		_index=$((_index+1))
	done
	echo "${_services_json}"
}

create_apps_json() {
	local _apps_json="$1"

	if [ ! -f "${_apps_json}" ]; then
		while read -r -d '' template_apps_json<<-EOF
{
    "apps": {
}
}
EOF
		do
			# This avoid read returning error from not finding a newline termination
			:
		done
		echo "${template_apps_json}" > "${_apps_json}"
	fi
}

# Update an apps.json file with a new preloaded app
# Arguments:
#
# $1: Application name
# $2: Release version
#
# Result:
# Updated apps.json in $DATA_VOLUME and the app json as output for further processing
install_app() {
	local _appName
	local _api_env
	local _apps_json
	local _version
	local _commitID
	local _appID
	local _svcID
	local _appUUID
	local _commitID
	local _imageId
	local _releaseId
	local _json
	local _bootable
	local _isHost="false"
	_appName="$1"
	_version="$2"
	_api_env="${BALENA_API_ENV}"
	_apps_json="${DATA_VOLUME}/apps.json"

	[ -z "${_appName}" ] && echo "Application name needs to be defined" && return 1
	[ -z "${_version}" ] && echo "Release version needs to be defined" && return 1

	_appID=$(balena_api_appID_from_appName "${_appName}" "${_api_env}")
	_bootable=$(balena_api_is_bootable "${_appName}" "${_api_env}")
	if [ "${_bootable}" = "true" ]; then
		_isHost="true"
	fi
	if [ -n "${_appID}" ] && [ "${_appID}" != "null" ]; then
		_json=$(balena_api_fetch_image_json "${_appName}" "${_api_env}" "${_version}")
		[ -z "${_json}" ] && return
		_releaseId=$(echo "${_json}" | jq --raw-output '.d[0].is_part_of__release[0].id')
		_appUUID=$(balena_api_appUUID_from_appName "${_appName}" "${_api_env}")
		_commitID=$(fetch_commitID_from_app "${_appName}" "${_version}" "${_api_env}")
		_image_sizes=$(calculate_image_sizes "${_json}")
	else
		>&2 echo "[${_appName}] Application not found in ${_api_env}"
		return  1
	fi

	while read -r -d '' entry_json_app<<-EOF
{
   "${_appUUID}": {
        "commit": "${_commitID}",
        "uuid": "${_appUUID}",
        "releaseId": ${_releaseId},
        "appId": ${_appID},
        "releaseVersion": "${_version}",
        "name": "${_appName}",
        "isHost": "${_isHost}",
        "services": {}
    }
}
EOF
	do
		# This avoid read returning error from not finding a newline termination
		:
	done

	create_apps_json "${_apps_json}"
	tmpfile=$(mktemp)
	jq --argjson entry "${entry_json_app}" '.apps += $entry' "${_apps_json}" > "${tmpfile}"
	entry_json_services=$(update_hostos_services "${_json}" "${_version}" "${_appUUID}" "${_appID}")
	jq --argjson entry "${entry_json_services}" '.apps["'"${_appUUID}"'"].services += $entry' "${tmpfile}" > "${_apps_json}"
	rm -rf "${tmpfile}"
	echo "${_image_sizes}"
}
