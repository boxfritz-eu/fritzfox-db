-- Generic PostgreSQL Schema & Maintenance Initialization
-- Enables pg_cron and configures automated maintenance and backup jobs.

-- 1. Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Scheduled maintenance via pg_cron (runs VACUUM ANALYZE every night at 03:00)
SELECT cron.schedule(
    'nightly-maintenance',
    '0 3 * * *',
    'VACUUM ANALYZE;'
);

-- 3. Scheduled automated backup via pg_cron (runs every night at 02:22)
DO $cron_block$
DECLARE
    backup_cmd text;
BEGIN
    backup_cmd := format(
        'COPY (SELECT 1) TO PROGRAM ''sh -c "pg_dump -U %s -d %s -Fc -f /backups/%s_$(date +%%Y%%m%%d_%%H%%M%%S).dump"''',
        current_user,
        current_database(),
        current_database()
    );
    PERFORM cron.schedule('full-dump-nightly', '22 2 * * *', backup_cmd);
END $cron_block$;
