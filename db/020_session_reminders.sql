-- The Journey: what the session reminder texts need to know (see LEVEL_REMINDERS in journey-submit).
alter table public.journey_people
  add column if not exists signup_at timestamptz,   -- when they signed up (Level 0)
  add column if not exists level1_on date,          -- the Level 1 Saturday they chose when signing up
  add column if not exists level1_at timestamptz,
  add column if not exists level4_at timestamptz,
  add column if not exists rem_level int,           -- the session we last texted them about
  add column if not exists rem_count int not null default 0,   -- texts sent for that session (max 2)
  add column if not exists rem_at timestamptz;
