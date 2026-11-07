# PostgreSQL Setup, Integration & Maintenance Guide (db-howto)

This guide provides step-by-step instructions for operating, maintaining, and integrating with the PostgreSQL database. It is designed to be clear and self-contained so that this database configuration can eventually be moved into its own dedicated repository.

---

## 📑 Table of Contents

1. [Architecture & Storage Concept](#1-architecture--storage-concept)
2. [Spinning up PostgreSQL with Docker Compose](#2-spinning-up-postgresql-with-docker-compose)
3. [Connecting to the Database](#3-connecting-to-the-database)
   3.1. [pgAdmin (Web GUI)](#31-pgadmin-web-gui)
   3.2. [Config Table & Moving Average Window](#32-config-table--moving-average-window)
4. [Using the CLI Tooling in this Repo](#4-using-the-cli-tooling-in-this-repo)
5. [Standardized Access for Other Scripts & Services](#5-standardized-access-for-other-scripts--services)
6. [VCS-Style Version Tracking & Manual Restore](#6-vcs-style-version-tracking--manual-restore)
7. [Backup & Disaster Recovery (`pg_dump` / `pg_restore`)](#7-backup--disaster-recovery-pg_dump--pg_restore)
8. [Routine Maintenance & Health Checks](#8-routine-maintenance--health-checks)

---

## 1. Architecture & Storage Concept

The database implements a **dual-layer Version Control System (VCS) model** with JSONB storage:

```text
┌─────────────────────────────────────────────────────────────┐
│                    dataset_snapshots                        │
│ - id (PK)                                                   │
│ - source ('boxmatrix-raw', 'converter-specs', etc.)         │
│ - captured_at (TIMESTAMPTZ)                                 │
│ - full_data (JSONB, the entire unmodified snapshot payload) │
└──────────────────────────────┬──────────────────────────────┘
                               │ 1:N
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                      item_revisions                         │
│ - id (PK)                                                   │
│ - snapshot_id (FK -> dataset_snapshots.id)                  │
│ - source ('boxmatrix-raw', 'converter-specs', etc.)         │
│ - item_key ('FRITZ!Box 7590 AX', '7590', etc.)              │
│ - version (1, 2, 3... per item)                             │
│ - data_hash (SHA-256 hash of item JSONB)                    │
│ - data (JSONB, individual entity object)                   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                   current_items (SQL View)                  │
│ Returns the latest revision (HEAD) for each item per source │
└─────────────────────────────────────────────────────────────┘
```

### Key Advantages

1. **Granular item queries:** Query any FRITZ!Box model directly by name or attributes via JSONB GIN indexes.
2. **Snapshot reproducibility:** Every batch execution preserves the complete raw JSON snapshot exactly as received.
3. **Deduplication:** An unchanged item between sync runs does not produce a redundant revision in `item_revisions`.
4. **Multi-Service namespaces:** Multiple independent scripts (raw scraper, converter, enricher) can write to the same database using distinct `source` identifiers.

---

## 2. Spinning up PostgreSQL with Docker Compose

The database runs PostgreSQL 16 on Alpine Linux with automatic schema initialization via `./db/init.sql`. It can be run either by building locally from `./db/Dockerfile` or by pulling the pre-built container from GitHub Container Registry (`ghcr.io/kugeleis/boxmatrix-loader-db:latest`).

### Starting the Container

To start PostgreSQL in the background (will build locally if image is not pulled):

```bash
docker compose up -d --build
```

Or just:

```bash
docker compose up -d
```

### Checking Container Health

```bash
docker compose ps
```

You should see:

```text
NAME                 IMAGE                STATUS                   PORTS
boxmatrix-postgres   postgres:16-alpine   Up (healthy)             0.0.0.0:5432->5432/tcp
```

### Viewing Container Logs

```bash
docker compose logs -f postgres
```

### Stopping the Container

To stop the database (preserves all data in the `pgdata` volume):

```bash
docker compose stop
```

To take down the container without removing stored data:

```bash
docker compose down
```

> ⚠️ **Warning:** Running `docker compose down -v` will **delete** the database volume. Avoid `-v` in production.

---

## 3. Connecting to the Database

### Credentials Source

Passwords live in `.env` at repo root (copy `.env.example` to `.env` and change the passwords — never commit `.env`).  Run `task up` to start the DB; it loads `.env` automatically via docker compose `env_file`.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `POSTGRES_USER` | Admin / database owner (also used by postgres entrypoint) | `boxmatrix` |
| `POSTGRES_PASSWORD` | Admin password | `boxmatrix` |
| `POSTGRES_DB` | Database name | `boxmatrix` |
| `POSTGRES_PORT` | Host port | `5432` |
| `WRITER_PASSWORD` | Writer role password | `boxmatrix_writer_pw` |
| `READER_PASSWORD` | Reader role password | `boxmatrix_reader_pw` |

Connection strings:

```text
postgresql://boxmatrix_writer:boxmatrix_writer_pw@localhost:5432/boxmatrix
postgresql://boxmatrix_reader:boxmatrix_reader_pw@localhost:5432/boxmatrix
```

### Interactive `psql` Shell

Admin (owner) via compose:

```bash
docker compose exec -it postgres psql -U boxmatrix -d boxmatrix
```

Write / read roles:

```bash
docker compose exec -it postgres psql -U boxmatrix_writer -d boxmatrix
docker compose exec -it postgres psql -U boxmatrix_reader -d boxmatrix
```

### 3.1. pgAdmin (Web GUI)

pgAdmin 4 provides a web-based GUI for managing the PostgreSQL database. It is included in `docker-compose.yml` and exposes on port 8090.

**Starting and Stopping:**

```bash
# Start pgAdmin (runs in background)
docker compose up -d pgadmin

# Stop pgAdmin
docker compose stop pgadmin
```

**Accessing pgAdmin:**
Open <http://localhost:8090> in your web browser.

**Credentials:**

- Email: `PGADMIN_DEFAULT_EMAIL` (from compose env, defaults to `boxmatrix@boxmatrix.local`)
- Password: `PGADMIN_DEFAULT_PASSWORD` (same as `POSTGRES_PASSWORD`)

**Server Connection:**

- A pre-configured server entry for `postgres` is available via `./pgadmin/servers.json`
- **Host:** `postgres` (the docker service name)
- **Port:** 5432
- **Maintenance DB:** `boxmatrix`
- **Username:** `${POSTGRES_USER:-boxmatrix}`
- **Password:** `${POSTGRES_PASSWORD:-boxmatrix}`

**Important Notes:**

- Credentials are expanded at container startup from `.env` values via a Python script, so passwords are never hardcoded in the committed `servers.json` template
- `PGADMIN_REPLACE_SERVERS_ON_STARTUP` is set to `true` to re-apply server definitions on each container start
- `PGADMIN_DISABLE_POSTFIX` is set to `"1"` to prevent email delivery issues in homeserver environments
- The `pgadmin-data` volume persists all configuration and session data

**Accessing via Docker:**

```bash
# List running containers
docker compose ps

# View logs
docker compose logs -f pgadmin
```

**Important Security Note:**
This setup is designed for homeserver use. For production environments, consider:

- Adding TLS (set `PGADMIN_ENABLE_TLS` and provide certificates)
- Using proper authentication mechanisms
- Restricting access via firewall or reverse proxy

### 3.2. Config Table & Moving Average Window

The `model_price_moving_avg` view averages prices per model over a configurable look-back window. The window size (in days) lives in the `app_config` table so it can be updated without restarting the container:

```sql
CREATE TABLE IF NOT EXISTS app_config (
    key TEXT PRIMARY KEY,
    value TEXT
);

INSERT INTO app_config (key, value) VALUES ('window_days', '60')
ON CONFLICT (key) DO NOTHING;
```

### Updating the Window

Change the look-back period via direct SQL or a psql client:

```sql
UPDATE app_config SET value = '30' WHERE key = 'window_days';
```

The view query below automatically uses the new value on every execution — no container restart needed.

### View Definition

```sql
CREATE OR REPLACE VIEW model_price_moving_avg AS
SELECT
    name,
    AVG(price) FILTER (WHERE NOT is_used) AS avg_price_new,
    AVG(price) FILTER (WHERE is_used) AS avg_price_used
FROM prices
WHERE date_time >= NOW() - INTERVAL '1 day' * (
    SELECT value::int FROM app_config WHERE key = 'window_days'
)
GROUP BY name;
```

The `prices` table (written by `ebay-prices`) and the moving average view let consumers query recent pricing trends without scanning the entire price history.

### Prices Table Schema

The `prices` table stores one row per FRITZ!Box model:

```sql
CREATE TABLE IF NOT EXISTS prices (
    ebay_id      BIGINT PRIMARY KEY,
    name         TEXT NOT NULL,
    price        NUMERIC(12,2),
    is_used      BOOLEAN,
    description  TEXT,
    date_time TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Columns:**

| Column | Type | Description |
| :--- | :--- | :--- |
| `ebay_id` | `BIGINT` | Primary key - eBay item ID of the sold listing |
| `name` | `TEXT` | FRITZ!Box model name (e.g., `FRITZ!Box 7590 AX`) |
| `price` | `NUMERIC(12,2)` | Sale price of the listing |
| `is_used` | `BOOLEAN` | Whether the listing was used (`true`) or new (`false`) |
| `description` | `TEXT` | Description of the sold item |
| `date_time` | `TIMESTAMPTZ` | When the listing was sold (default: `now()`) |

---

## 4. Using the CLI Tooling in this Repo

This repository provides built-in CLI commands to manage and interact with the database.

### 4.0 Taskfile (Docker / Maintenance Tasks)

All Docker lifecycle and maintenance tasks are driven by `Taskfile.yml`:

```bash
task up            # Start DB with build (loads .env)
task down          # Stop DB, preserving data
task rebuild       # Rebuild image and recreate container
task backup        # Timestamped compressed backup to ./backups
task backup-host   # Stream compressed backup directly to host backups/
task restore FILE=backups/boxmatrix.dump   # Restore from a dump
task maintain      # VACUUM ANALYZE both tables
task sizes         # Show table/index sizes
task shell         # Interactive psql
task health        # Check container status and quick query
```

### 4.1 Initialize or Verify Schema (`boxmatrix-db init`)

```bash
uv run boxmatrix-db init
```

### 4.2 Upload Existing JSON File (`boxmatrix-db upload`)

Uploads any existing `output/boxen.json` (or any other JSON dataset) into PostgreSQL:

```bash
# Upload default output/boxen.json
uv run boxmatrix-db upload

# Upload a specific file under a custom namespace
uv run boxmatrix-db upload path/to/dataset.json --source converter-specs
```

### 4.3 Check Current Items (`boxmatrix-db status`)

Lists the active models currently stored in the database:

```bash
uv run boxmatrix-db status --limit 15
```

### 4.4 Inspect Item Revision History (`boxmatrix-db history`)

Shows all versions recorded for a given model:

```bash
uv run boxmatrix-db history "FRITZ!Box 7590 AX"
```

### 4.5 Restore Item to an Earlier Version (`boxmatrix-db restore`)

Safely rolls back a model to an earlier version (creates a new HEAD revision):

```bash
uv run boxmatrix-db restore "FRITZ!Box 7590 AX" 1
```

### 4.6 Automatic Ingestion during BoxMatrix Sync

You can tell `boxmatrix-loader` to persist models directly into PostgreSQL during sync:

```bash
uv run boxmatrix-loader --save-to-db
```

Or configure it permanently in `config/config.yaml`:

```yaml
database:
  enabled: true
  url: "postgresql://boxmatrix:boxmatrix@localhost:5432/boxmatrix"
  source_name: "boxmatrix-raw"
```

---

## 5. Standardized Access for Other Scripts & Services

Any external script (e.g., converter, normalizer, or API) can interact with this database using standard SQL or any language's PostgreSQL client.

`boxmatrix-clean` is the primary consumer of the `converter-specs` namespace, reading raw data via the `current_items` view and writing the cleaned pipeline output back as new revisions.

### 5.1 Recommended Convention

Use the `source` column to isolate your service:

- `boxmatrix-raw`: Raw scraped wiki data from this repo (written by `boxmatrix-loader`).
- `converter-specs`: Cleaned / converted specifications (written by `boxmatrix-clean`).
- `custom-enrichment`: Data enriched with third-party prices or release info.

### 5.2 Python Example (`asyncpg` / `psycopg`)

```python
import json
import hashlib
import asyncpg


def compute_hash(data: dict) -> str:
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


async def save_converted_item(conn, source: str, item_key: str, item_data: dict):
    data_hash = compute_hash(item_data)

    # 1. Fetch latest version
    latest = await conn.fetchrow(
        "SELECT version, data_hash FROM item_revisions WHERE source = $1 AND item_key = $2 ORDER BY version DESC LIMIT 1",
        source,
        item_key,
    )

    if latest is None:
        # First version
        await conn.execute(
            "INSERT INTO item_revisions (source, item_key, version, data_hash, data) VALUES ($1, $2, 1, $3, $4::jsonb)",
            source,
            item_key,
            data_hash,
            json.dumps(item_data),
        )
    elif latest["data_hash"] != data_hash:
        # Changed -> create next version
        await conn.execute(
            "INSERT INTO item_revisions (source, item_key, version, data_hash, data) VALUES ($1, $2, $3, $4, $5::jsonb)",
            source,
            item_key,
            latest["version"] + 1,
            data_hash,
            json.dumps(item_data),
        )
    # If latest["data_hash"] == data_hash, skip (no change)
```

### 5.3 Querying the Latest Data via SQL

Any service can read the active dataset with a single query against `current_items`:

```sql
-- Get all active items from the converter
SELECT item_key, version, data, created_at
FROM current_items
WHERE source = 'converter-specs';

-- Find models with Wi-Fi 6 (802.11ax) using JSONB containment
SELECT item_key, data->>'name' as name
FROM current_items
WHERE source = 'boxmatrix-raw'
  AND data->'features'->'802.11ax' ? 'Yes';
```

---

## 6. VCS-Style Version Tracking & Manual Restore

If data is corrupted, erroneously modified, or deleted by a script, you can inspect previous revisions and manually restore previous states.

### 6.1 Inspecting Revision History

Open `psql` (or run a query from your DB client):

```sql
SELECT version, created_at, data_hash, data
FROM item_revisions
WHERE source = 'boxmatrix-raw' AND item_key = 'FRITZ!Box 7590 AX'
ORDER BY version ASC;
```

### 6.2 Comparing Differences (Diff)

Inspect what changed between version 1 and version 2:

```sql
SELECT
    v1.data as version_1_data,
    v2.data as version_2_data
FROM item_revisions v1
JOIN item_revisions v2
  ON v1.source = v2.source
 AND v1.item_key = v2.item_key
 AND v2.version = 2
WHERE v1.source = 'boxmatrix-raw'
  AND v1.item_key = 'FRITZ!Box 7590 AX'
  AND v1.version = 1;
```

### 6.3 Restoring an Item to an Earlier Version (Safe Revert)

To restore version `1` as the active state without deleting history (just like `git revert`):

```sql
INSERT INTO item_revisions (source, item_key, version, data_hash, data)
SELECT
    source,
    item_key,
    (SELECT MAX(version) + 1 FROM item_revisions WHERE source = 'boxmatrix-raw' AND item_key = 'FRITZ!Box 7590 AX'),
    data_hash,
    data
FROM item_revisions
WHERE source = 'boxmatrix-raw'
  AND item_key = 'FRITZ!Box 7590 AX'
  AND version = 1;
```

`current_items` will now immediately reflect version 1's data under the new version number.

### 6.4 Restoring an Entire Dataset from a Past Snapshot

To retrieve a past snapshot and re-export or review it:

```sql
-- Find previous snapshots
SELECT id, source, captured_at, item_count, metadata
FROM dataset_snapshots
WHERE source = 'boxmatrix-raw'
ORDER BY captured_at DESC;

-- Export full JSON payload of snapshot #2
SELECT full_data
FROM dataset_snapshots
WHERE id = 2;
```

---

## 7. Backup & Disaster Recovery (`pg_dump` / `pg_restore`)

### 7.1 Creating a Backup

Using the repo's `Taskfile` (writes to the `./backups` directory defined by `docker-compose.yml`):

```bash
task backup
```

Custom filename / directory: `task backup FILE=backups/weekly.dump`

Or using `docker compose` directly (writes inside container to `/backups`):

```bash
docker compose exec -t postgres pg_dump -U boxmatrix -d boxmatrix -F c -b -v -f /backups/backup_$(date +%Y%m%d_%H%M%S).dump
```

Or backup directly to your host machine (no bind mount needed):

```bash
docker compose exec -T postgres pg_dump -U boxmatrix -d boxmatrix -F c > backup_$(date +%Y%m%d_%H%M%S).dump
```

### 7.2 Restoring from a Backup

Using the repo's `Taskfile`:

```bash
# Restore from a dump file created by `task backup` or `task backup-host`
task restore FILE=backups/boxmatrix_YYYYMMDD_HHMMSS.dump
```

Or using `docker compose`:

```bash
docker compose exec -T postgres pg_restore -U boxmatrix -d boxmatrix --clean --if-exists -v < backup_file.dump
```

---

## 8. Routine Maintenance & Health Checks

### 8.1 Vacuum & Analyze

Using the `Taskfile`:

```bash
task maintain
```

Or manually via `psql`:

```sql
VACUUM ANALYZE dataset_snapshots;
VACUUM ANALYZE item_revisions;
```

### 8.2 Inspecting Table & Index Sizes

```sql
SELECT
    relname AS object_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

### 8.3 Re-indexing

If indexes become fragmented after thousands of revisions:

```sql
REINDEX TABLE item_revisions;
```
