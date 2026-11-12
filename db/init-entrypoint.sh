#!/bin/sh
set -e

# Entrypoint init script for PostgreSQL
# If custom init.sql is provided in /init/init.sql or /usr/local/share/postgresql/init/init.sql,
# execute that. Otherwise, execute default_init.sql.

INIT_FILE=""
if [ -f "/init/init.sql" ]; then
    INIT_FILE="/init/init.sql"
elif [ -f "/usr/local/share/postgresql/init/init.sql" ]; then
    INIT_FILE="/usr/local/share/postgresql/init/init.sql"
elif [ -f "/usr/local/share/postgresql/init/default_init.sql" ]; then
    INIT_FILE="/usr/local/share/postgresql/init/default_init.sql"
fi

if [ -n "$INIT_FILE" ]; then
    echo "Processing database initialization script: $INIT_FILE"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$INIT_FILE"
else
    echo "No initialization SQL file found."
fi
