-- ATOM ANIME Supabase Database Schema
-- Run this in your Supabase SQL editor to create the required tables

-- ============================================
-- PROFILES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,  -- Profile names must be unique
  pin_hash TEXT NOT NULL,
  avatar_color TEXT DEFAULT '#673AB7',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index on name for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_name ON profiles(name);

-- ============================================
-- DEVICE PROFILES TABLE (links devices to profiles)
-- ============================================
CREATE TABLE IF NOT EXISTS device_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL,
  profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  remember_pin BOOLEAN DEFAULT FALSE,
  linked_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure one device can only have one link per profile
  UNIQUE(device_id, profile_id)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_device_profiles_device ON device_profiles(device_id);
CREATE INDEX IF NOT EXISTS idx_device_profiles_profile ON device_profiles(profile_id);

-- ============================================
-- WATCH HISTORY TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS watch_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  anime_id TEXT NOT NULL,
  anime_title TEXT NOT NULL,
  cover_image TEXT,
  episode_number INTEGER NOT NULL,
  episode_id TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'sub',
  watched_seconds INTEGER DEFAULT 0,
  total_seconds INTEGER DEFAULT 0,
  completed BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure unique entry per profile/anime/episode/category
  UNIQUE(profile_id, anime_id, episode_number, category)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_watch_history_profile ON watch_history(profile_id);
CREATE INDEX IF NOT EXISTS idx_watch_history_anime ON watch_history(anime_id);
CREATE INDEX IF NOT EXISTS idx_watch_history_updated ON watch_history(updated_at DESC);

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================
-- Enable RLS on all tables (required for Supabase security)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE watch_history ENABLE ROW LEVEL SECURITY;

-- Allow anonymous access for all operations (since we're using PIN auth, not Supabase Auth)
-- In production, you may want to add more restrictive policies

CREATE POLICY "Allow anonymous read profiles" ON profiles
  FOR SELECT USING (true);

CREATE POLICY "Allow anonymous insert profiles" ON profiles
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow anonymous update profiles" ON profiles
  FOR UPDATE USING (true);

CREATE POLICY "Allow anonymous read device_profiles" ON device_profiles
  FOR SELECT USING (true);

CREATE POLICY "Allow anonymous insert device_profiles" ON device_profiles
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow anonymous update device_profiles" ON device_profiles
  FOR UPDATE USING (true);

CREATE POLICY "Allow anonymous delete device_profiles" ON device_profiles
  FOR DELETE USING (true);

CREATE POLICY "Allow anonymous read watch_history" ON watch_history
  FOR SELECT USING (true);

CREATE POLICY "Allow anonymous insert watch_history" ON watch_history
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow anonymous update watch_history" ON watch_history
  FOR UPDATE USING (true);

CREATE POLICY "Allow anonymous delete watch_history" ON watch_history
  FOR DELETE USING (true);

-- ============================================
-- HELPFUL VIEWS
-- ============================================

-- View for getting continue watching list
CREATE OR REPLACE VIEW continue_watching AS
SELECT 
  wh.id,
  wh.profile_id,
  wh.anime_id,
  wh.anime_title,
  wh.cover_image,
  wh.episode_number,
  wh.episode_id,
  wh.category,
  wh.watched_seconds,
  wh.total_seconds,
  wh.updated_at,
  ROUND((wh.watched_seconds::NUMERIC / NULLIF(wh.total_seconds, 0)) * 100, 1) as progress_percent
FROM watch_history wh
WHERE wh.completed = FALSE 
  AND wh.watched_seconds >= 30
ORDER BY wh.updated_at DESC;

-- ============================================
-- SETUP COMPLETE
-- ============================================
-- After running this migration:
-- 1. Go to your Supabase project Settings > API
-- 2. Copy the "Project URL" and "anon public" key
-- 3. Update lib/services/profile_service.dart with these values:
--    - SupabaseConfig.supabaseUrl = 'your-project-url'
--    - SupabaseConfig.supabaseAnonKey = 'your-anon-key'
