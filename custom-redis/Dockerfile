FROM redis:6.2

USER root

RUN apt-get update && apt-get install -y \
  less \
  vim \
  wget \
  && rm -rf /var/lib/apt/lists/*

USER redis

CMD ["redis-server"]
