FROM alpine:3.3
MAINTAINER Jonathan Short <jonathan.short@sendgrid.com>

RUN apk add --update rsyslog rsyslog-tls && rm -rf /var/cache/apk/*

ADD run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 514
EXPOSE 514/udp

CMD ["/run.sh"]