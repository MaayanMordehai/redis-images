FROM redis:6.2

ENV SHARED_VOLUME /shared

WORKDIR /
COPY entrypoint.sh /
COPY prestop.sh $SHARED_VOLUME/

ENTRYPOINT ["/entrypoint.sh"]
