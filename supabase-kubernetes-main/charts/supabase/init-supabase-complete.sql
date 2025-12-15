-- ============================================================================
-- SUPABASE COMPLETE DATABASE INITIALIZATION SCRIPT
-- ============================================================================
-- This script prepares a vanilla PostgreSQL database for Supabase services.
-- Run this on your PostgreSQL container before deploying Supabase to Kubernetes.
--
-- Usage: 
--   docker exec -i postgres psql -U postgres < init-supabase-complete.sql
--
-- Password: example123456 (change in production!)
-- ============================================================================

\set VERBOSITY terse
\set ON_ERROR_STOP off

-- ============================================================================
-- SECTION 1: CREATE ROLES WITH PROPER PERMISSIONS
-- ============================================================================

-- Create anon role (used by PostgREST for anonymous requests)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
    RAISE NOTICE 'Created role: anon';
  END IF;
END $$;

-- Create authenticated role (used by PostgREST for authenticated requests)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
    RAISE NOTICE 'Created role: authenticated';
  END IF;
END $$;

-- Create service_role (bypasses RLS)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    RAISE NOTICE 'Created role: service_role';
  END IF;
END $$;

-- Create supabase_admin (main admin role)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin LOGIN CREATEROLE CREATEDB REPLICATION BYPASSRLS PASSWORD 'example123456';
    RAISE NOTICE 'Created role: supabase_admin';
  ELSE
    ALTER ROLE supabase_admin LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create authenticator (used by PostgREST to switch roles)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'example123456';
    RAISE NOTICE 'Created role: authenticator';
  ELSE
    ALTER ROLE authenticator LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create supabase_auth_admin (used by GoTrue/Auth service)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin LOGIN NOINHERIT CREATEROLE PASSWORD 'example123456';
    RAISE NOTICE 'Created role: supabase_auth_admin';
  ELSE
    ALTER ROLE supabase_auth_admin LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create supabase_storage_admin (used by Storage service)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    CREATE ROLE supabase_storage_admin LOGIN NOINHERIT PASSWORD 'example123456';
    RAISE NOTICE 'Created role: supabase_storage_admin';
  ELSE
    ALTER ROLE supabase_storage_admin LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create supabase_functions_admin (used by Edge Functions)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_functions_admin') THEN
    CREATE ROLE supabase_functions_admin LOGIN NOINHERIT CREATEROLE PASSWORD 'example123456';
    RAISE NOTICE 'Created role: supabase_functions_admin';
  ELSE
    ALTER ROLE supabase_functions_admin LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create supabase_realtime_admin (used by Realtime service)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_realtime_admin') THEN
    CREATE ROLE supabase_realtime_admin LOGIN NOINHERIT PASSWORD 'example123456';
    RAISE NOTICE 'Created role: supabase_realtime_admin';
  ELSE
    ALTER ROLE supabase_realtime_admin LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create pgbouncer role (for connection pooling)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgbouncer') THEN
    CREATE ROLE pgbouncer LOGIN PASSWORD 'example123456';
    RAISE NOTICE 'Created role: pgbouncer';
  ELSE
    ALTER ROLE pgbouncer LOGIN PASSWORD 'example123456';
  END IF;
END $$;

-- Create dashboard_user role
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dashboard_user') THEN
    CREATE ROLE dashboard_user NOLOGIN;
    RAISE NOTICE 'Created role: dashboard_user';
  END IF;
END $$;

-- ============================================================================
-- SECTION 2: GRANT ROLE MEMBERSHIPS
-- ============================================================================

GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;
GRANT supabase_admin TO postgres;
GRANT anon TO supabase_admin;
GRANT authenticated TO supabase_admin;
GRANT service_role TO supabase_admin;

-- ============================================================================
-- SECTION 3: CREATE SCHEMAS
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS graphql_public;
CREATE SCHEMA IF NOT EXISTS supabase_functions;
CREATE SCHEMA IF NOT EXISTS supabase_migrations;

-- ============================================================================
-- SECTION 4: SET SCHEMA OWNERSHIP
-- ============================================================================

ALTER SCHEMA auth OWNER TO supabase_auth_admin;
ALTER SCHEMA storage OWNER TO supabase_storage_admin;
ALTER SCHEMA _realtime OWNER TO supabase_admin;
ALTER SCHEMA _analytics OWNER TO supabase_admin;
ALTER SCHEMA supabase_functions OWNER TO supabase_functions_admin;

-- ============================================================================
-- SECTION 5: GRANT SCHEMA PERMISSIONS
-- ============================================================================

-- Public schema
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO supabase_admin;
GRANT CREATE ON SCHEMA public TO supabase_auth_admin, supabase_storage_admin;

-- Auth schema
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role, postgres;

-- Storage schema
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role, postgres;

-- Realtime schemas
GRANT ALL ON SCHEMA _realtime TO supabase_admin, supabase_realtime_admin;
GRANT USAGE ON SCHEMA _realtime TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA realtime TO supabase_admin;
GRANT USAGE ON SCHEMA realtime TO anon, authenticated, service_role;

-- Analytics schema
GRANT ALL ON SCHEMA _analytics TO supabase_admin;
GRANT USAGE ON SCHEMA _analytics TO anon, authenticated, service_role;

-- Extensions schema
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role, supabase_admin;
GRANT ALL ON SCHEMA extensions TO supabase_admin;

-- GraphQL schema
GRANT USAGE ON SCHEMA graphql_public TO anon, authenticated, service_role;

-- Functions schema
GRANT ALL ON SCHEMA supabase_functions TO supabase_functions_admin;
GRANT USAGE ON SCHEMA supabase_functions TO postgres, anon, authenticated, service_role;

-- ============================================================================
-- SECTION 6: CREATE EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ============================================================================
-- SECTION 7: SET DEFAULT PRIVILEGES
-- ============================================================================

-- Default privileges for public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;

-- Default privileges for storage schema
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

-- ============================================================================
-- SECTION 8: DATABASE SETTINGS
-- ============================================================================

-- JWT settings (must match your values-external-db.yaml secret.jwt.secret)
ALTER DATABASE postgres SET "app.settings.jwt_secret" TO 'your-super-secret-jwt-token-with-at-least-32-characters-long';
ALTER DATABASE postgres SET "app.settings.jwt_exp" TO '3600';

-- Search path
ALTER DATABASE postgres SET search_path TO public, extensions;

-- ============================================================================
-- SECTION 9: GRANT DATABASE PERMISSIONS
-- ============================================================================

GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_admin;
GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_auth_admin;
GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_storage_admin;
GRANT CONNECT ON DATABASE postgres TO anon, authenticated, service_role;
GRANT CREATE ON DATABASE postgres TO supabase_storage_admin;
GRANT CREATE ON DATABASE postgres TO supabase_auth_admin;

-- ============================================================================
-- SECTION 10: AUTH HELPER FUNCTIONS
-- ============================================================================
-- NOTE: These functions will be created by the Auth service migrations.
-- We only set up the schema ownership here. The Auth service (GoTrue) will
-- create its own functions with the correct ownership during migration.
-- DO NOT create auth.uid(), auth.role(), auth.email() here - let GoTrue do it.

-- Grant schema ownership with grant option so Auth can create objects
GRANT ALL ON SCHEMA auth TO supabase_auth_admin WITH GRANT OPTION;

-- Ensure supabase_auth_admin can create functions in auth schema
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA auth 
  GRANT ALL ON FUNCTIONS TO supabase_auth_admin;

-- Grant execute on any future functions to the API roles
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth 
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- ============================================================================
-- SECTION 11: REALTIME SETUP
-- ============================================================================

-- Create realtime schema migrations table
CREATE TABLE IF NOT EXISTS _realtime.schema_migrations (
  version BIGINT PRIMARY KEY,
  inserted_at TIMESTAMP WITHOUT TIME ZONE
);

-- Grant permissions on realtime tables
GRANT ALL ON TABLE _realtime.schema_migrations TO supabase_admin, supabase_realtime_admin;

-- ============================================================================
-- SECTION 12: STORAGE MIGRATIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS storage.migrations (
  id INTEGER PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  hash VARCHAR(40) NOT NULL,
  executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

GRANT ALL ON TABLE storage.migrations TO supabase_storage_admin;

-- ============================================================================
-- SECTION 13: SUPABASE FUNCTIONS SETUP
-- ============================================================================

CREATE TABLE IF NOT EXISTS supabase_functions.migrations (
  version TEXT PRIMARY KEY,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS supabase_functions.hooks (
  id BIGSERIAL PRIMARY KEY,
  hook_table_id INTEGER NOT NULL,
  hook_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  request_id BIGINT
);

GRANT ALL ON TABLE supabase_functions.migrations TO supabase_functions_admin;
GRANT ALL ON TABLE supabase_functions.hooks TO supabase_functions_admin;
GRANT ALL ON SEQUENCE supabase_functions.hooks_id_seq TO supabase_functions_admin;

-- ============================================================================
-- SECTION 14: FINAL GRANTS AND CLEANUP
-- ============================================================================

-- Ensure all roles have proper schema access
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;

-- Grant table access in each schema
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL TABLES IN SCHEMA _realtime TO supabase_admin, supabase_realtime_admin;
GRANT ALL ON ALL TABLES IN SCHEMA _analytics TO supabase_admin;
GRANT ALL ON ALL TABLES IN SCHEMA supabase_functions TO supabase_functions_admin;

-- Grant sequence access
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA _realtime TO supabase_admin, supabase_realtime_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA supabase_functions TO supabase_functions_admin;

-- ============================================================================
-- SECTION 15: VALIDATION
-- ============================================================================

DO $$
DECLARE
  role_count INTEGER;
  schema_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO role_count FROM pg_roles 
  WHERE rolname IN ('anon', 'authenticated', 'service_role', 'authenticator', 
                    'supabase_admin', 'supabase_auth_admin', 'supabase_storage_admin');
  
  SELECT COUNT(*) INTO schema_count FROM information_schema.schemata 
  WHERE schema_name IN ('auth', 'storage', '_realtime', '_analytics', 'extensions');
  
  IF role_count >= 7 AND schema_count >= 5 THEN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'SUPABASE DATABASE INITIALIZATION COMPLETE!';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Roles created: %', role_count;
    RAISE NOTICE 'Schemas created: %', schema_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Default password for all roles: example123456';
    RAISE NOTICE 'Change this in production!';
    RAISE NOTICE '============================================';
  ELSE
    RAISE WARNING 'Initialization may be incomplete. Check logs above.';
  END IF;
END $$;

-- ============================================================================
-- END OF SCRIPT
-- ============================================================================

