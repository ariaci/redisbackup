FROM redis:latest

COPY tmp/redisbackup.sh /sbin/redisbackup.sh
COPY tmp/redisbackup_getcfg.sh /sbin/getcfg

RUN mkdir /etc/config
COPY tmp/redisbackup.conf /etc/config/redisbackup.conf

ENV TZ=Europe/Berlin

VOLUME /backup

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/sbin/redisbackup.sh"]
