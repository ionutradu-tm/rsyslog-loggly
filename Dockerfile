FROM ubuntu:20.04

RUN apt-get update && apt install -y  rsyslog && apt-get clean

ADD run.sh /run.sh
ADD rsyslog.conf /etc/
RUN chmod +x /run.sh

EXPOSE 514
EXPOSE 514/udp

CMD ["/run.sh"]