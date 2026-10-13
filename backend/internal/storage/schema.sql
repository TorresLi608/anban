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
 CREATE TABLE IF NOT EXISTS anban_files (id text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS anban_push_settings (
 user_id text PRIMARY KEY REFERENCES anban_users(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT false,
 time_zone text NOT NULL DEFAULT 'Asia/Shanghai',
 last_success timestamptz,
 last_error text NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS anban_push_jobs (
 user_id text NOT NULL REFERENCES anban_push_settings(user_id) ON DELETE CASCADE,
 key text NOT NULL,
 due_at timestamptz NOT NULL,
 daily_time text NOT NULL DEFAULT '',
 retry_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,key)
);
CREATE INDEX IF NOT EXISTS anban_push_jobs_due ON anban_push_jobs(due_at,retry_at);
