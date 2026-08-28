-- ============================================================
-- WakeGuard — Initial Supabase Schema
-- ============================================================
-- Run this in the Supabase SQL Editor after creating the project.
-- It creates all tables, Row Level Security policies, and the
-- auto-profile trigger needed by the Python backend and Flutter app.

-- ── Profiles (1:1 with Supabase Auth users) ────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- ── Desktop devices registered under an account ─────────────
CREATE TABLE IF NOT EXISTS devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES profiles(id) ON DELETE CASCADE,
  device_name   TEXT NOT NULL,
  platform      TEXT,            -- 'windows', 'linux', 'macos'
  api_host      TEXT,            -- current LAN IP, updated on heartbeat
  api_port      INT DEFAULT 8765,
  registered_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at  TIMESTAMPTZ
);

-- ── Pairing codes (replaces in-memory PairingManager) ──────
CREATE TABLE IF NOT EXISTS pairing_codes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id  UUID REFERENCES devices(id) ON DELETE CASCADE,
  code       TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── Sessions (replaces JSONL file summaries) ────────────────
CREATE TABLE IF NOT EXISTS sessions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id      UUID REFERENCES devices(id) ON DELETE CASCADE,
  user_id        UUID REFERENCES profiles(id) ON DELETE CASCADE,
  started_at     TIMESTAMPTZ NOT NULL,
  ended_at       TIMESTAMPTZ,
  duration_s     FLOAT,
  avg_attention  FLOAT,
  avg_perclos    FLOAT,
  alert_count    INT DEFAULT 0,
  safety_score   FLOAT,
  alerts_by_type JSONB DEFAULT '{}'::jsonb,
  metadata       JSONB DEFAULT '{}'::jsonb
);

-- ── Per-second telemetry (replaces frame_sample JSONL) ──────
CREATE TABLE IF NOT EXISTS telemetry (
  id             BIGSERIAL PRIMARY KEY,
  session_id     UUID REFERENCES sessions(id) ON DELETE CASCADE,
  ts             TIMESTAMPTZ NOT NULL,
  attention      FLOAT,
  perclos        FLOAT,
  ema_drowsy     FLOAT,
  pitch          FLOAT,
  yaw            FLOAT,
  roll           FLOAT,
  pose_valid     BOOLEAN,
  alert          TEXT,
  blinks_per_min FLOAT
);

-- ── Alert events (replaces alert/clear JSONL entries) ───────
CREATE TABLE IF NOT EXISTS alert_events (
  id         BIGSERIAL PRIMARY KEY,
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  ts         TIMESTAMPTZ NOT NULL,
  alert      TEXT NOT NULL,
  event_type TEXT NOT NULL,      -- 'alert' or 'clear'
  fired_for  FLOAT
);

-- ── Indexes for common queries ──────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sessions_user    ON sessions (user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_device  ON sessions (device_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_session ON telemetry (session_id, ts);
CREATE INDEX IF NOT EXISTS idx_alerts_session    ON alert_events (session_id, ts);
CREATE INDEX IF NOT EXISTS idx_devices_user      ON devices (user_id);
CREATE INDEX IF NOT EXISTS idx_pairing_device    ON pairing_codes (device_id);

-- ── Row Level Security ─────────────────────────────────────
ALTER TABLE profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE telemetry     ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_events  ENABLE ROW LEVEL SECURITY;
ALTER TABLE pairing_codes ENABLE ROW LEVEL SECURITY;

-- Users can only see their own data
CREATE POLICY "profiles_own" ON profiles
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "devices_own" ON devices
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "sessions_own" ON sessions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "telemetry_own" ON telemetry
  FOR ALL USING (
    session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid())
  );

CREATE POLICY "alert_events_own" ON alert_events
  FOR ALL USING (
    session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid())
  );

CREATE POLICY "pairing_own" ON pairing_codes
  FOR ALL USING (
    device_id IN (SELECT id FROM devices WHERE user_id = auth.uid())
  );

-- ── Auto-create profile on signup ──────────────────────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (new.id, new.raw_user_meta_data->>'display_name');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the trigger first if it already exists (idempotent)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
