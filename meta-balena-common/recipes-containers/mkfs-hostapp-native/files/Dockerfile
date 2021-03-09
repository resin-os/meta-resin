FROM debian:bullseye

VOLUME /mnt/sysroot/inactive

RUN apt-get update && apt-get install -y \
	ca-certificates \
	iptables \
	btrfs-progs \
	duperemove \
	rsync

# Fixes issue with Docker expecting iptables when the distro is using nftables
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy

COPY create.* /usr/bin/

CMD [ "/usr/bin/create.ext4" ]
