FROM debian:bullseye

ARG OLD_PG_VERSION=13
ARG NEW_PG_VERSION=16

ENV OLD_PG_VERSION=$OLD_PG_VERSION
ENV NEW_PG_VERSION=$NEW_PG_VERSION

RUN apt-get update && \
    apt-get install -y wget gnupg2 lsb-release passwd util-linux locales && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=en_US.UTF-8 && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y postgresql-$OLD_PG_VERSION postgresql-$NEW_PG_VERSION && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY migrate.sh /migrate.sh
RUN chmod +x /migrate.sh

CMD ["/migrate.sh"]