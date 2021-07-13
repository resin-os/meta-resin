#!/bin/sh

set -o errexit
set -o nounset

DOCKER_TIMEOUT=20 # Wait 20 seconds for docker to start
DATA_VOLUME=/resin-data
BUILD=/build
PARTITION_SIZE=${PARTITION_SIZE:-1024}
DOCKER_HOST=unix:///var/run/docker.sock

finish() {
	# Make all files owned by the build system
	chown -R "$USER_ID:$USER_GID" "${BUILD}"
}
trap finish EXIT

. /balena-apps.inc

adjust_partition_size() {
	local _image_size_bytes="$1"
	MB_TO_BYTES=$(( 1024*1024 ))
	_image_size_bytes=$(( PARTITION_SIZE*MB_TO_BYTES + _image_size_bytes ))
	PARTITION_SIZE=$(( _image_size_bytes/MB_TO_BYTES ))
}

# Create user
echo "[INFO] Creating and setting $USER_ID:$USER_GID."
groupadd -g "$USER_GID" docker-disk-group || true
useradd -u "$USER_ID" -g "$USER_GID" -p "" docker-disk-user || true

mkdir -p $DATA_VOLUME/docker
mkdir -p $DATA_VOLUME/resin-data

# Start docker
echo "Starting docker daemon with $BALENA_STORAGE storage driver."
dockerd -H "$DOCKER_HOST" --data-root="$DATA_VOLUME/docker" -s "$BALENA_STORAGE" -b none --experimental &
echo "Waiting for docker to become ready.."
STARTTIME="$(date +%s)"
ENDTIME="$STARTTIME"
while [ ! -S /var/run/docker.sock ]
do
    if [ $((ENDTIME - STARTTIME)) -le $DOCKER_TIMEOUT ]; then
        sleep 1 && ENDTIME=$((ENDTIME + 1))
    else
        echo "Timeout while waiting for docker to come up."
        exit 1
    fi
done
echo "Docker started."

# Pull in arch specific hello-world image and tag it balena-healthcheck-image
echo "Pulling ${HELLO_REPOSITORY}:latest..."
docker pull --platform "${HOSTAPP_PLATFORM}" "${HELLO_REPOSITORY}"
docker tag "${HELLO_REPOSITORY}" balena-healthcheck-image
docker rmi "${HELLO_REPOSITORY}"
docker save balena-healthcheck-image > ${BUILD}/balena-healthcheck-image.tar

# Pull in the supervisor image as a separate app until it converges in the hostOS
if [ -n "${SUPERVISOR_APP}" ] && [ -n "${SUPERVISOR_VERSION}" ]; then
	image_sizes=$(install_app "${SUPERVISOR_APP}" "${SUPERVISOR_VERSION}")
        adjust_partition_size "${image_sizes}"
	_supervisor_image=$(jq -r '.apps | .[] | select(.name=="'"${SUPERVISOR_APP}"'") | .services | .[].image' "${DATA_VOLUME}/apps.json")
	_supervisor_image_id=$(imageid_from_digest "${_supervisor_image}")
	docker tag "${_supervisor_image_id}" "${SUPERVISOR_APP}":"${SUPERVISOR_VERSION}"
fi

# Pull in hostos apps, both space-separated or colon-separated lists are accepted
for image_name in $(echo ${HOSTOS_APPS} | tr ":" " "); do
	image_sizes=$(install_app "${image_name}" "${HOSTOS_VERSION}")
        adjust_partition_size "${image_sizes}"
done

echo "Stopping docker..."
kill -TERM "$(cat /var/run/docker.pid)"
# don't let wait() error out and crash the build if the docker daemon has already been stopped
wait "$(cat /var/run/docker.pid)" || true

# Export the apps.json meta-data
cp "${DATA_VOLUME}/apps.json" "${BUILD}"/

# Export the final data filesystem
dd if=/dev/zero of=${BUILD}/resin-data.img bs=1M count=0 seek="${PARTITION_SIZE}"

# Usage type default, block size 4k defined in recipe. See https://github.com/tytso/e2fsprogs/issues/50
mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 -T default -b "${FS_BLOCK_SIZE}"  -i 8192 -d "${DATA_VOLUME}" -F "${BUILD}/resin-data.img"
