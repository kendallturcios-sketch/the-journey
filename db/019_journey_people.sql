-- The Journey: who finished Level 2, their spiritual gifts, and the optional text-message consent.
-- Written and read only by the journey-submit server (service key). RLS is on with no policies,
-- so the public API key can't see any of it.
create table if not exists public.journey_people (
  email         text primary key,                 -- lower-cased
  first_name    text,
  last_name     text,
  phone         text,
  lang          text not null default 'en',
  pco_person    text,                             -- Planning Center person id, from their last submission
  sms_ok        boolean not null default false,   -- ticked the optional text-message box
  sms_at        timestamptz,                      -- when they agreed
  level2_at     timestamptz,
  level3_at     timestamptz,
  gifts         text[],
  gifts_at      timestamptz,
  remind_count  int not null default 0,           -- gift-survey reminder texts sent (max 2)
  reminded_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table public.journey_people enable row level security;
revoke all on public.journey_people from anon, authenticated;
create index if not exists journey_people_waiting on public.journey_people (level2_at)
  where level2_at is not null and level3_at is null and gifts is null;
