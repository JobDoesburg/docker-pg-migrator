FROM debian:bullseye

ARG OLD_PG_VERSION=13
ARG NEW_PG_VERSION=16

ENV OLD_PG_VERSION=$OLD_PG_VERSION
ENV NEW_PG_VERSION=$NEW_PG_VERSION

# Install tools and PostgreSQL versions
RUN apt-get update && \
    apt-get install -y wget gnupg2 lsb-release sudo && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y postgresql-$OLD_PG_VERSION postgresql-$NEW_PG_VERSION && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create postgres user and working directories
RUN mkdir -p /var/lib/postgresql/old /var/lib/postgresql/new /upgrade && \
    chown -R postgres:postgres /var/lib/postgresql /upgrade

# Copy the migration script
COPY migrate.sh /upgrade/migrate.sh
RUN chmod +x /upgrade/migrate.sh && chown postgres:postgres /upgrade/migrate.sh

# Switch to postgres user
USER postgres

# Set working directory and default command
WORKDIR /upgrade
CMD ["/upgrade/migrate.sh"]