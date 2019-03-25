FROM alpine:3.3

RUN apk add --update rsyslog rsyslog-tls && rm -rf /var/cache/apk/*

ADD run.sh /run.sh
ADD rsyslog.conf /etc/
RUN chmod +x /run.sh

EXPOSE 514
EXPOSE 514/udp

CMD ["/run.sh"]