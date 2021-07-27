FROM maayanmord/custom-redis:6.2
WORKDIR /var/lib/redis
ENV SHARED_VOLUME /config
CMD ["redis-server", "/config/sentinel.conf", "--sentinel"]
