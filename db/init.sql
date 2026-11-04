-- BoxMatrix PostgreSQL Schema Initialization
-- Dual-table VCS architecture with JSONB storage

CREATE TABLE IF NOT EXISTS dataset_snapshots (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(64) NOT NULL DEFAULT 'boxmatrix-raw',
    captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    item_count INTEGER NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    full_data JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_snapshots_source_captured ON dataset_snapshots (source, captured_at DESC);

CREATE TABLE IF NOT EXISTS item_revisions (
    id BIGSERIAL PRIMARY KEY,
    snapshot_id BIGINT REFERENCES dataset_snapshots(id) ON DELETE SET NULL,
    source VARCHAR(64) NOT NULL DEFAULT 'boxmatrix-raw',
    item_key TEXT NOT NULL,
    version INTEGER NOT NULL,
    data_hash VARCHAR(64) NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_item_source_version UNIQUE (source, item_key, version)
);

CREATE INDEX IF NOT EXISTS idx_revisions_lookup ON item_revisions (source, item_key, version DESC);
CREATE INDEX IF NOT EXISTS idx_revisions_hash ON item_revisions (source, item_key, data_hash);
CREATE INDEX IF NOT EXISTS idx_revisions_created_at ON item_revisions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_revisions_data_gin ON item_revisions USING gin (data);

CREATE OR REPLACE VIEW current_items AS
SELECT DISTINCT ON (source, item_key)
    id,
    snapshot_id,
    source,
    item_key,
    version,
    data_hash,
    data,
    created_at
FROM item_revisions
ORDER BY source, item_key, version DESC;

-- Denormalized boxes table: one row per box, key fields extracted for fast queries
CREATE TABLE IF NOT EXISTS boxes (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(64) NOT NULL DEFAULT 'converter-specs',
    name TEXT NOT NULL,
    model TEXT,
    wifi_generation TEXT,
    internet TEXT[],
    lan_ports INTEGER,
    wifi_speed INTEGER,
    has_24ghz BOOLEAN DEFAULT FALSE,
    has_5ghz BOOLEAN DEFAULT FALSE,
    has_cable BOOLEAN DEFAULT FALSE,
    has_dsl BOOLEAN DEFAULT FALSE,
    has_fiber BOOLEAN DEFAULT FALSE,
    has_mobile BOOLEAN DEFAULT FALSE,
    firmware TEXT,
    intro_date BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_boxes_source_name UNIQUE (source, name)
);

-- Trigger to auto-update updated_at on row modification
CREATE OR REPLACE FUNCTION update_boxes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_boxes_updated_at ON boxes;
CREATE TRIGGER trigger_boxes_updated_at
    BEFORE UPDATE ON boxes
    FOR EACH ROW
    EXECUTE FUNCTION update_boxes_updated_at();

-- Separate write / read roles (passwords match .env defaults; edit both to change)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'boxmatrix_writer') THEN
        CREATE ROLE "boxmatrix_writer" WITH LOGIN PASSWORD 'boxmatrix_writer_pw';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'boxmatrix_reader') THEN
        CREATE ROLE "boxmatrix_reader" WITH LOGIN PASSWORD 'boxmatrix_reader_pw';
    END IF;
END $$;

GRANT CONNECT ON DATABASE "boxmatrix" TO "boxmatrix_writer", "boxmatrix_reader";
GRANT USAGE ON SCHEMA public TO "boxmatrix_writer", "boxmatrix_reader";

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "boxmatrix_writer";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "boxmatrix_writer";

GRANT SELECT ON ALL TABLES IN SCHEMA public TO "boxmatrix_reader";
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO "boxmatrix_reader";
