FROM postgres:18

ARG APP_NAME=PostgreSQL
LABEL org.opencontainers.image.title="${APP_NAME} Database" \
      org.opencontainers.image.description="PostgreSQL 18 with pg_cron enabled"

# Install pg_cron from the PostgreSQL repository that is already configured in the official
# image (PG_MAJOR is set by the base image). This installs the pg_cron extension package.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends "postgresql-${PG_MAJOR}-cron"; \
    rm -rf /var/lib/apt/lists/*

# Preload pg_cron extension
CMD ["postgres", \
     "-c", "shared_preload_libraries=pg_cron", \
     "-c", "cron.database_name=boxmatrix"]

# Put SQL files into /usr/local/share/postgresql/init
RUN mkdir -p /usr/local/share/postgresql/init /docker-entrypoint-initdb.d
COPY default_init.sql /usr/local/share/postgresql/init/default_init.sql
COPY init.sql /usr/local/share/postgresql/init/init.sql
COPY init-entrypoint.sh /docker-entrypoint-initdb.d/01-init.sh
RUN chmod +x /docker-entrypoint-initdb.d/01-init.sh

HEALTHCHECK --interval=5s --timeout=5s --retries=10 --start-period=10s \
    CMD pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"
