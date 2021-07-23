FROM maayanmord/custom-redis:6.2
WORKDIR /var/lib/redis
ENV SHARED_VOLUME /shared
CMD ["redis-server", "--sentinel", "$SHARED_VOLUME/sentinel.conf"]
