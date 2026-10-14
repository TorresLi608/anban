CREATE TABLE IF NOT EXISTS anban_health_options (key text PRIMARY KEY, options jsonb NOT NULL CHECK (jsonb_typeof(options) = 'array'));
CREATE TABLE IF NOT EXISTS anban_android_release (
 id boolean PRIMARY KEY DEFAULT true CHECK (id),
 revision bigint NOT NULL DEFAULT 0,
 enabled boolean NOT NULL DEFAULT false,
 release jsonb,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS anban_apks (
 id text PRIMARY KEY,
 size bigint NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
 CREATE TABLE IF NOT EXISTS anban_users (id text PRIMARY KEY, username text NOT NULL UNIQUE, password_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
 CREATE TABLE IF NOT EXISTS anban_sessions (token_hash text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, expires_at timestamptz NOT NULL);
 CREATE INDEX IF NOT EXISTS anban_sessions_expiry ON anban_sessions(expires_at);
 CREATE TABLE IF NOT EXISTS anban_vaults (user_id text PRIMARY KEY REFERENCES anban_users(id) ON DELETE CASCADE, revision bigint NOT NULL DEFAULT 0, updated_at timestamptz NOT NULL DEFAULT now(), data jsonb);
 CREATE TABLE IF NOT EXISTS anban_files (id text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, filename text NOT NULL DEFAULT '', content_type text NOT NULL DEFAULT 'application/octet-stream', size bigint NOT NULL DEFAULT 0, minio_key text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now());
 ALTER TABLE anban_files ADD COLUMN IF NOT EXISTS filename text NOT NULL DEFAULT '';
 ALTER TABLE anban_files ADD COLUMN IF NOT EXISTS content_type text NOT NULL DEFAULT 'application/octet-stream';
 ALTER TABLE anban_files ADD COLUMN IF NOT EXISTS size bigint NOT NULL DEFAULT 0;
 ALTER TABLE anban_files ADD COLUMN IF NOT EXISTS minio_key text NOT NULL DEFAULT '';
 CREATE TABLE IF NOT EXISTS anban_file_shares (token text PRIMARY KEY, file_id text NOT NULL REFERENCES anban_files(id) ON DELETE CASCADE, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now());
