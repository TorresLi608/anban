CREATE TABLE IF NOT EXISTS anban_health_options (key text PRIMARY KEY, options jsonb NOT NULL CHECK (jsonb_typeof(options) = 'array'));
 CREATE TABLE IF NOT EXISTS anban_users (id text PRIMARY KEY, username text NOT NULL UNIQUE, password_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
 CREATE TABLE IF NOT EXISTS anban_sessions (token_hash text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, expires_at timestamptz NOT NULL);
 CREATE INDEX IF NOT EXISTS anban_sessions_expiry ON anban_sessions(expires_at);
 CREATE TABLE IF NOT EXISTS anban_vaults (user_id text PRIMARY KEY REFERENCES anban_users(id) ON DELETE CASCADE, revision bigint NOT NULL DEFAULT 0, updated_at timestamptz NOT NULL DEFAULT now(), data jsonb);
 CREATE TABLE IF NOT EXISTS anban_files (id text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now());
