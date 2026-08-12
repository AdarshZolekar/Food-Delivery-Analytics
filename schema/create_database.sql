-- =============================================================================
-- FILE:        schema/create_database.sql
-- Description: Database initialisation — extensions, schema, and roles
-- Target:      PostgreSQL 14+
-- =============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'food_reader') THEN
        CREATE ROLE food_reader;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'food_writer') THEN
        CREATE ROLE food_writer;
    END IF;
END $$;

-- Performance settings (tune to your hardware)
ALTER DATABASE food_delivery SET work_mem = '256MB';
ALTER DATABASE food_delivery SET effective_cache_size = '4GB';
ALTER DATABASE food_delivery SET random_page_cost = 1.1;
ALTER DATABASE food_delivery SET checkpoint_completion_target = 0.9;

GRANT USAGE ON SCHEMA public TO food_reader, food_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO food_reader;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO food_writer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO food_writer;

DO $$
BEGIN
    RAISE NOTICE 'food_delivery database initialised.';
    RAISE NOTICE 'Next step: run schema/create_tables.sql';
END $$;
