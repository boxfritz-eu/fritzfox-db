# syntax=docker/dockerfile:1

# PostgreSQL 18 (official Debian image) with pg_cron enabled for BoxMatrix
FROM postgres:18

LABEL org.opencontainers.image.title="BoxMatrix PostgreSQL Database" \
      org.opencontainers.image.description="PostgreSQL 18 with pg_cron enabled" \
      org.opencontainers.image.source="https://github.com/Kugeleis/boxmatrix-loader"

# Install pg_cron from the PGDG repo that is already configured in the official
# image (PG_MAJOR is set by the base image). No compiler or build tools needed.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends "postgresql-${PG_MAJOR}-cron"; \
    rm -rf /var/lib/apt/lists/*

# Init scripts run alphabetically, only on an empty data directory, and against
# POSTGRES_DB (default: boxmatrix). The extension must live in the database
# named by cron.database_name (see CMD below), so both have to match.
COPY init.sql /docker-entrypoint-initdb.d/20-init.sql

# pg_cron needs to be preloaded. Exec-form CMD cannot expand env vars, so the
# database name is hardcoded; keep it in sync with POSTGRES_DB.
# Note: a `command:` in docker-compose replaces this CMD.
CMD ["postgres", \
     "-c", "shared_preload_libraries=pg_cron", \
     "-c", "cron.database_name=boxmatrix"]

# -h 127.0.0.1 forces TCP: during first-time init the temporary server only
# listens on the unix socket, so a socket check would report "healthy" too early.
HEALTHCHECK --interval=5s --timeout=5s --retries=10 --start-period=10s \
    CMD pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"
