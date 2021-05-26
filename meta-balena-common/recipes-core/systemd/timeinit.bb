# Copyright 2018-2020 Balena Ltd.
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

DESCRIPTION = "Initialize system clock at boot"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${BALENA_COREBASE}/COPYING.Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

RDEPENDS_${PN} += "os-helpers-time"

SRC_URI = " \
    file://timeinit-buildtime.service \
    file://timeinit-buildtime.sh \
    file://fake-hwclock \
    file://fake-hwclock.service \
    file://fake-hwclock-update.service \
    file://fake-hwclock-update.timer \
    file://timeinit-rtc.service \
    file://timeinit-rtc.sh \
    file://timesync-https.service \
    file://timesync-https.sh \
    file://time-set.target \
    file://time-sync.conf \
    "
S = "${WORKDIR}"

inherit allarch systemd

SYSTEMD_SERVICE_${PN} = " \
	timeinit-buildtime.service \
	fake-hwclock.service \
	fake-hwclock-update.service \
	fake-hwclock-update.timer \
	timeinit-rtc.service \
	timesync-https.service \
	time-set.target \
	"

do_install() {
    install -d ${D}${base_sbindir}
    install -d ${D}${bindir}
    install -d ${D}${systemd_unitdir}/system
    install -d ${D}/etc/fake-hwclock
    install -d ${D}${sysconfdir}/systemd/system/time-sync.target.d/
    install -m 0775 ${WORKDIR}/timeinit-buildtime.sh ${D}${bindir}
    install -m 0775 ${WORKDIR}/timeinit-rtc.sh ${D}${bindir}
    install -m 0775 ${WORKDIR}/timesync-https.sh ${D}${bindir}
    install -m 0775 ${WORKDIR}/fake-hwclock ${D}${base_sbindir}
    install -m 0644 ${WORKDIR}/timeinit-buildtime.service ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/fake-hwclock.service ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/fake-hwclock-update.service ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/fake-hwclock-update.timer ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/timeinit-rtc.service ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/timesync-https.service ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/time-set.target ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/time-sync.conf ${D}${sysconfdir}/systemd/system/time-sync.target.d/
}
