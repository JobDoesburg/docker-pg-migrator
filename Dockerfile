FROM debian:bullseye

ARG OLD_PG_VERSION=13
ARG NEW_PG_VERSION=16

ENV OLD_PG_VERSION=$OLD_PG_VERSION
ENV NEW_PG_VERSION=$NEW_PG_VERSION

RUN apt-get update && \
    apt-get install -y wget gnupg2 lsb-release && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y postgresql-$OLD_PG_VERSION postgresql-$NEW_PG_VERSION && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir /upgrade && \
    mkdir /var/log/pg_upgrade

COPY migrate.sh /upgrade/migrate.sh
RUN chmod +x /upgrade/migrate.sh

CMD ["/upgrade/migrate.sh"]