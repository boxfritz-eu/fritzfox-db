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

# pg_cron needs to be preloaded.
# Defaults to POSTGRES_DB or 'postgres' via entrypoint wrapper if not overridden by docker-compose command.
CMD ["sh", "-c", "exec postgres -c shared_preload_libraries=pg_cron -c cron.database_name=\"${POSTGRES_DB:-postgres}\""]

COPY init.sql /docker-entrypoint-initdb.d/20-init.sql

# -h 127.0.0.1 forces TCP: during first-time init the temporary server only
# listens on the unix socket, so a socket check would report "healthy" too early.
HEALTHCHECK --interval=5s --timeout=5s --retries=10 --start-period=10s \
    CMD pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"
