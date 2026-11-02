FROM postgres:16-alpine

LABEL org.opencontainers.image.title="BoxMatrix PostgreSQL Database" \
      org.opencontainers.image.description="PostgreSQL 16 container pre-initialized with BoxMatrix VCS JSONB schema" \
      org.opencontainers.image.source="https://github.com/Kugeleis/boxmatrix-loader"

COPY init.sql /docker-entrypoint-initdb.d/init.sql

HEALTHCHECK --interval=5s --timeout=5s --retries=5 \
  CMD pg_isready -U "${POSTGRES_USER:-boxmatrix}" -d "${POSTGRES_DB:-boxmatrix}"
