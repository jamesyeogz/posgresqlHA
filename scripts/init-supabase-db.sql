-- Supabase Database Initialization Script
-- Run this script on your Patroni PostgreSQL cluster before deploying Supabase
-- Usage: psql -h <host> -p <port> -U <username> -d <database> -f scripts/init-supabase-db.sql
-- 
-- For external agents' PostgreSQL databases:
-- psql -h <agent-host> -p <agent-port> -U <agent-username> -d <agent-database> -f scripts/init-supabase-db.sql

\echo 'Starting Supabase database initialization...'

-- Check if we're connected to a valid PostgreSQL database
\echo 'Verifying database connection...'
SELECT version();

-- Create required extensions
\echo 'Creating extensions...'

-- Check if required extensions are available
DO $$
DECLARE
    missing_extensions TEXT[] := ARRAY[]::TEXT[];
    ext TEXT;
    -- Core required extensions (available in standard PostgreSQL)
    required_extensions TEXT[] := ARRAY[
        'uuid-ossp', 'pgcrypto', 'pg_stat_statements'
    ];
    -- Supabase-specific extensions (installed via custom Dockerfile)
    supabase_extensions TEXT[] := ARRAY[
        'pgjwt', 'pgsodium', 'pgvector', 'pg_cron', 'http', 'pg_hashids'
    ];
    -- Optional extensions (nice to have but not critical)
    optional_extensions TEXT[] := ARRAY[
        'pg_graphql', 'pg_jsonschema', 'wrappers', 'vault', 'pg_net'
    ];
BEGIN
    -- Check required extensions
    FOREACH ext IN ARRAY required_extensions
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_available_extensions 
            WHERE name = ext
        ) THEN
            missing_extensions := array_append(missing_extensions, ext);
        END IF;
    END LOOP;
    
    -- Check Supabase extensions (warn if missing)
    FOREACH ext IN ARRAY supabase_extensions
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_available_extensions 
            WHERE name = ext
        ) THEN
            RAISE WARNING 'Supabase extension % is not available - some features may not work', ext;
        END IF;
    END LOOP;
    
    -- Check optional extensions
    FOREACH ext IN ARRAY optional_extensions
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_available_extensions 
            WHERE name = ext
        ) THEN
            RAISE WARNING 'Optional extension % is not available', ext;
        END IF;
    END LOOP;
    
    IF array_length(missing_extensions, 1) > 0 THEN
        RAISE EXCEPTION 'Required extensions are missing: %', array_to_string(missing_extensions, ', ');
    END IF;
END
$$;

-- Install required extensions (standard PostgreSQL)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Install Supabase extensions (from custom Dockerfile)
DO $$
BEGIN
    -- pgjwt - JWT token generation/verification (required for Auth)
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pgjwt";
        RAISE NOTICE 'Extension pgjwt installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pgjwt extension: %', SQLERRM;
    END;
    
    -- pgsodium - Encryption (required for Vault)
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pgsodium";
        RAISE NOTICE 'Extension pgsodium installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pgsodium extension: %', SQLERRM;
    END;
    
    -- pgvector - Vector similarity search (for AI/ML features)
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "vector";
        RAISE NOTICE 'Extension vector (pgvector) installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create vector extension: %', SQLERRM;
    END;
    
    -- pg_cron - Scheduled jobs
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pg_cron";
        RAISE NOTICE 'Extension pg_cron installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pg_cron extension: %', SQLERRM;
    END;
    
    -- http - HTTP client extension
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "http";
        RAISE NOTICE 'Extension http installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create http extension: %', SQLERRM;
    END;
    
    -- pg_hashids - Short unique IDs
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pg_hashids";
        RAISE NOTICE 'Extension pg_hashids installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pg_hashids extension: %', SQLERRM;
    END;
END
$$;

-- Install optional extensions (may not be available)
DO $$
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pg_graphql";
        RAISE NOTICE 'Extension pg_graphql installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pg_graphql extension: %', SQLERRM;
    END;
    
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pg_jsonschema";
        RAISE NOTICE 'Extension pg_jsonschema installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pg_jsonschema extension: %', SQLERRM;
    END;
    
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "wrappers";
        RAISE NOTICE 'Extension wrappers installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create wrappers extension: %', SQLERRM;
    END;
    
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "vault";
        RAISE NOTICE 'Extension vault installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create vault extension: %', SQLERRM;
    END;
    
    BEGIN
        CREATE EXTENSION IF NOT EXISTS "pg_net";
        RAISE NOTICE 'Extension pg_net installed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create pg_net extension: %', SQLERRM;
    END;
END
$$;

-- Create Supabase schemas
\echo 'Creating schemas...'
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS graphql_public;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS net;
CREATE SCHEMA IF NOT EXISTS vault;

-- Create roles
\echo 'Creating roles...'
DO $$
DECLARE
    role_name TEXT;
    required_roles TEXT[] := ARRAY[
        'anon', 'authenticated', 'service_role', 'supabase_admin',
        'supabase_auth_admin', 'supabase_storage_admin', 'dashboard_user'
    ];
BEGIN
    -- Check if current user has CREATEROLE privilege
    IF NOT (
        SELECT rolcreaterole FROM pg_roles WHERE rolname = current_user
    ) THEN
        RAISE WARNING 'Current user % does not have CREATEROLE privilege. Some roles may not be created.', current_user;
    END IF;
    
    -- Create required roles
    FOREACH role_name IN ARRAY required_roles
    LOOP
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
                EXECUTE format('CREATE ROLE %I NOLOGIN', role_name);
                RAISE NOTICE 'Created role: %', role_name;
            ELSE
                RAISE NOTICE 'Role % already exists', role_name;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to create role %: %', role_name, SQLERRM;
        END;
    END LOOP;
END
$$;

-- Grant basic permissions
\echo 'Setting up basic permissions...'
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

-- Set up default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;

-- Auth schema setup
\echo 'Setting up auth schema...'
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Create auth.users table
CREATE TABLE IF NOT EXISTS auth.users (
    instance_id UUID,
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aud VARCHAR(255),
    role VARCHAR(255),
    email VARCHAR(255) UNIQUE,
    encrypted_password VARCHAR(255),
    email_confirmed_at TIMESTAMPTZ,
    invited_at TIMESTAMPTZ,
    confirmation_token VARCHAR(255),
    confirmation_sent_at TIMESTAMPTZ,
    recovery_token VARCHAR(255),
    recovery_sent_at TIMESTAMPTZ,
    email_change_token_new VARCHAR(255),
    email_change VARCHAR(255),
    email_change_sent_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    raw_app_meta_data JSONB,
    raw_user_meta_data JSONB,
    is_super_admin BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    phone TEXT UNIQUE,
    phone_confirmed_at TIMESTAMPTZ,
    phone_change TEXT,
    phone_change_token VARCHAR(255),
    phone_change_sent_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current VARCHAR(255) DEFAULT '',
    email_change_confirm_status SMALLINT DEFAULT 0,
    banned_until TIMESTAMPTZ,
    reauthentication_token VARCHAR(255),
    reauthentication_sent_at TIMESTAMPTZ,
    is_sso_user BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    is_anonymous BOOLEAN DEFAULT FALSE
);

-- Create auth.refresh_tokens table
CREATE TABLE IF NOT EXISTS auth.refresh_tokens (
    instance_id UUID,
    id BIGSERIAL PRIMARY KEY,
    token VARCHAR(255) UNIQUE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    revoked BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    parent VARCHAR(255),
    session_id UUID
);

-- Create auth.instances table
CREATE TABLE IF NOT EXISTS auth.instances (
    id UUID PRIMARY KEY,
    uuid UUID,
    raw_base_config TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create auth.audit_log_entries table
CREATE TABLE IF NOT EXISTS auth.audit_log_entries (
    instance_id UUID,
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payload JSON,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    ip_address VARCHAR(64) DEFAULT ''
);

-- Create auth.flow_state table
CREATE TABLE IF NOT EXISTS auth.flow_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    auth_code TEXT NOT NULL,
    code_challenge_method TEXT NOT NULL,
    code_challenge TEXT NOT NULL,
    provider_type TEXT NOT NULL,
    provider_access_token TEXT,
    provider_refresh_token TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    authentication_method TEXT NOT NULL
);

-- Create auth.sessions table
CREATE TABLE IF NOT EXISTS auth.sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    factor_id UUID,
    aal TEXT,
    not_after TIMESTAMPTZ,
    refreshed_at TIMESTAMP,
    user_agent TEXT,
    ip INET,
    tag TEXT
);

-- Create auth.mfa_amr_claims table
-- Note: The 'id' column and primary key constraint will be added by migration 20221011041400_add_mfa_indexes
-- We create it without 'id' to match the expected migration state
-- If the table exists with an old structure (with id and primary key), we need to clean it up
DO $$
BEGIN
    -- Drop the table if it exists with the wrong structure (has id column with primary key)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'auth' 
        AND table_name = 'mfa_amr_claims' 
        AND column_name = 'id'
    ) THEN
        -- Check if there's a primary key constraint
        IF EXISTS (
            SELECT 1 FROM information_schema.table_constraints 
            WHERE table_schema = 'auth' 
            AND table_name = 'mfa_amr_claims' 
            AND constraint_type = 'PRIMARY KEY'
        ) THEN
            -- Drop the old primary key constraint
            ALTER TABLE auth.mfa_amr_claims DROP CONSTRAINT IF EXISTS mfa_amr_claims_pkey;
            ALTER TABLE auth.mfa_amr_claims DROP CONSTRAINT IF EXISTS mfa_amr_claims_pkey1;
            ALTER TABLE auth.mfa_amr_claims DROP CONSTRAINT IF EXISTS amr_id_pk;
            -- Drop the id column so migration can add it
            ALTER TABLE auth.mfa_amr_claims DROP COLUMN IF EXISTS id;
        END IF;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS auth.mfa_amr_claims (
    session_id UUID NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    authentication_method TEXT NOT NULL
);

-- Create auth.mfa_factors table
CREATE TABLE IF NOT EXISTS auth.mfa_factors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    friendly_name TEXT,
    factor_type TEXT NOT NULL CHECK (factor_type IN ('totp', 'webauthn')),
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    secret TEXT
);

-- Create auth.mfa_challenges table
CREATE TABLE IF NOT EXISTS auth.mfa_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    factor_id UUID NOT NULL REFERENCES auth.mfa_factors(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    verified_at TIMESTAMPTZ,
    ip_address INET NOT NULL
);

-- Create auth.one_time_tokens table
CREATE TABLE IF NOT EXISTS auth.one_time_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_type TEXT NOT NULL CHECK (token_type IN ('confirmation_token', 'reauthentication_token', 'recovery_token', 'email_change_token_new', 'email_change_token_current', 'phone_change_token')),
    token_hash TEXT NOT NULL,
    relates_to TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Storage schema setup
\echo 'Setting up storage schema...'
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

-- Create storage.buckets table
CREATE TABLE IF NOT EXISTS storage.buckets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    public BOOLEAN DEFAULT FALSE,
    avif_autodetection BOOLEAN DEFAULT FALSE,
    file_size_limit BIGINT,
    allowed_mime_types TEXT[],
    owner_id TEXT
);

-- Create storage.objects table
CREATE TABLE IF NOT EXISTS storage.objects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id TEXT REFERENCES storage.buckets(id),
    name TEXT,
    owner UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB,
    version TEXT,
    owner_id TEXT,
    path_tokens TEXT[] GENERATED ALWAYS AS (string_to_array(name, '/')) STORED
);

-- Create storage.s3_multipart_uploads table
CREATE TABLE IF NOT EXISTS storage.s3_multipart_uploads (
    id TEXT PRIMARY KEY,
    in_progress_size BIGINT DEFAULT 0,
    upload_signature TEXT,
    bucket_id TEXT REFERENCES storage.buckets(id),
    key TEXT NOT NULL,
    version TEXT,
    owner_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    user_metadata JSONB
);

-- Create storage.s3_multipart_uploads_parts table
CREATE TABLE IF NOT EXISTS storage.s3_multipart_uploads_parts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    upload_id TEXT REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE,
    size BIGINT DEFAULT 0,
    part_number INT,
    bucket_id TEXT REFERENCES storage.buckets(id),
    key TEXT,
    etag TEXT,
    owner_id TEXT,
    version TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Realtime schema setup
\echo 'Setting up realtime schema...'
GRANT USAGE ON SCHEMA _realtime TO service_role;

-- Create _realtime.subscription table
CREATE TABLE IF NOT EXISTS _realtime.subscription (
    id BIGSERIAL PRIMARY KEY,
    subscription_id UUID NOT NULL,
    entity REGCLASS NOT NULL,
    filters JSONB DEFAULT '[]'::JSONB NOT NULL,
    claims JSONB NOT NULL,
    claims_role TEXT GENERATED ALWAYS AS (claims ->> 'role') STORED,
    created_at TIMESTAMP DEFAULT timezone('utc', NOW()) NOT NULL
);

-- Create _realtime.schema_migrations table
CREATE TABLE IF NOT EXISTS _realtime.schema_migrations (
    version BIGINT PRIMARY KEY,
    inserted_at TIMESTAMP DEFAULT NOW()
);

-- Analytics schema setup
\echo 'Setting up analytics schema...'
GRANT USAGE ON SCHEMA _analytics TO service_role;

-- Create _analytics.page_views table
CREATE TABLE IF NOT EXISTS _analytics.page_views (
    id BIGSERIAL PRIMARY KEY,
    page_url TEXT NOT NULL,
    referrer TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    session_id UUID,
    user_id UUID REFERENCES auth.users(id)
);

-- Create indexes for performance
\echo 'Creating indexes...'
CREATE INDEX IF NOT EXISTS users_email_idx ON auth.users(email);
CREATE INDEX IF NOT EXISTS users_phone_idx ON auth.users(phone);
CREATE INDEX IF NOT EXISTS users_instance_id_idx ON auth.users(instance_id);
CREATE INDEX IF NOT EXISTS refresh_tokens_token_idx ON auth.refresh_tokens(token);
CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_idx ON auth.refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS audit_log_entries_instance_id_idx ON auth.audit_log_entries(instance_id);
CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON auth.sessions(user_id);
-- Note: user_id_created_at_idx and factor_id_created_at_idx will be created by migration 20221011041400_add_mfa_indexes
-- We skip them here to avoid conflicts
CREATE INDEX IF NOT EXISTS mfa_factors_user_id_idx ON auth.mfa_factors(user_id);
CREATE INDEX IF NOT EXISTS objects_bucket_id_idx ON storage.objects(bucket_id);
CREATE INDEX IF NOT EXISTS objects_name_idx ON storage.objects(name);
CREATE INDEX IF NOT EXISTS subscription_subscription_id_idx ON _realtime.subscription(subscription_id);

-- Enable Row Level Security
\echo 'Enabling Row Level Security...'
ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Create basic RLS policies
\echo 'Creating basic RLS policies...'

-- Auth users policies
CREATE POLICY "Users can view own user data" ON auth.users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own user data" ON auth.users
    FOR UPDATE USING (auth.uid() = id);

-- Storage buckets policies
CREATE POLICY "Public buckets are viewable by everyone" ON storage.buckets
    FOR SELECT USING (public = true);

CREATE POLICY "Users can view own buckets" ON storage.buckets
    FOR SELECT USING (auth.uid() = owner);

-- Storage objects policies
CREATE POLICY "Public objects are viewable by everyone" ON storage.objects
    FOR SELECT USING (bucket_id IN (SELECT id FROM storage.buckets WHERE public = true));

CREATE POLICY "Users can view own objects" ON storage.objects
    FOR SELECT USING (auth.uid() = owner);

CREATE POLICY "Users can insert own objects" ON storage.objects
    FOR INSERT WITH CHECK (auth.uid() = owner);

CREATE POLICY "Users can update own objects" ON storage.objects
    FOR UPDATE USING (auth.uid() = owner);

CREATE POLICY "Users can delete own objects" ON storage.objects
    FOR DELETE USING (auth.uid() = owner);

-- Create helper functions
\echo 'Creating helper functions...'

-- Function to get current user ID
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE SQL STABLE
AS $$
    SELECT COALESCE(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid
$$;

-- Function to get current user role
CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT
LANGUAGE SQL STABLE
AS $$
    SELECT COALESCE(
        nullif(current_setting('request.jwt.claim.role', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
    )::text
$$;

-- Function to get current user email
CREATE OR REPLACE FUNCTION auth.email()
RETURNS TEXT
LANGUAGE SQL STABLE
AS $$
    SELECT COALESCE(
        nullif(current_setting('request.jwt.claim.email', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
    )::text
$$;

-- Grant permissions on functions
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role;

-- Insert initial data
\echo 'Inserting initial data...'

-- Insert default bucket for avatars
INSERT INTO storage.buckets (id, name, public) 
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Insert default bucket for public files
INSERT INTO storage.buckets (id, name, public) 
VALUES ('public', 'public', true)
ON CONFLICT (id) DO NOTHING;

-- Create a sample user (optional - remove in production)
-- INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
-- VALUES (
--     gen_random_uuid(),
--     'admin@example.com',
--     crypt('password123', gen_salt('bf')),
--     NOW(),
--     NOW(),
--     NOW(),
--     '{"provider": "email", "providers": ["email"]}',
--     '{"name": "Admin User"}',
--     false
-- );

-- Final validation
\echo 'Performing final validation...'

DO $$
DECLARE
    validation_errors TEXT[] := ARRAY[]::TEXT[];
    error_msg TEXT;
BEGIN
    -- Check if all required schemas exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        validation_errors := array_append(validation_errors, 'auth schema missing');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'storage') THEN
        validation_errors := array_append(validation_errors, 'storage schema missing');
    END IF;
    
    -- Check if all required roles exist
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        validation_errors := array_append(validation_errors, 'anon role missing');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        validation_errors := array_append(validation_errors, 'authenticated role missing');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        validation_errors := array_append(validation_errors, 'service_role role missing');
    END IF;
    
    -- Check if critical tables exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        validation_errors := array_append(validation_errors, 'auth.users table missing');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        validation_errors := array_append(validation_errors, 'storage.buckets table missing');
    END IF;
    
    -- Check if required extensions are installed
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp') THEN
        validation_errors := array_append(validation_errors, 'uuid-ossp extension not installed');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
        validation_errors := array_append(validation_errors, 'pgcrypto extension not installed');
    END IF;
    
    -- Report validation results
    IF array_length(validation_errors, 1) > 0 THEN
        RAISE EXCEPTION 'Validation failed: %', array_to_string(validation_errors, ', ');
    ELSE
        RAISE NOTICE 'All validations passed successfully!';
    END IF;
END
$$;

\echo 'Supabase database initialization completed successfully!'
\echo 'Database Information:'
\echo '  Host: %HOSTNAME%'
\echo '  Port: %PORT%'
\echo '  Database: %DATABASE%'
\echo '  User: %USER%'
\echo ''
\echo 'Next steps:'
\echo '1. Configure your Supabase services to connect to this database'
\echo '2. Update connection strings in your Supabase configuration'
\echo '3. Test the connection with: psql -h <host> -p <port> -U <user> -d <database> -c "SELECT 1;"'
\echo '4. Deploy Supabase services pointing to this database'
\echo '5. Set up proper authentication and authorization rules'
