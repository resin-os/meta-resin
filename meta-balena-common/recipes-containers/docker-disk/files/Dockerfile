# This should match the balena-engine version
FROM docker:19.03.13-dind

RUN apk add --update util-linux shadow e2fsprogs && rm -rf /var/cache/apk/*
ADD entry.sh /entry.sh
RUN chmod a+x /entry.sh

VOLUME /resin-data

CMD /entry.sh
