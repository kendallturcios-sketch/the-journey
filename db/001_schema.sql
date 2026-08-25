-- =============================================================
--  THE JOURNEY  ·  Arise Miami SDA Church
--  Supabase / Postgres schema  ·  v2.0
--
--  PROGRAM SHAPE
--    4 levels (a.k.a. sessions). One session each, not a course.
--    Taught monthly on Sabbath:
--      Level 1 → 1st Sabbath   Level 3 → 3rd Sabbath
--      Level 2 → 2nd Sabbath   Level 4 → 4th Sabbath
--    Every level runs every month → 12 cycles per year.
--    A missed level is retaken at next month's occurrence.
--
--  COMPLETION RULE
--    A level is COMPLETE only when BOTH are true:
--      1. attendance recorded at an occurrence of that level
--      2. the in-app lesson content marked finished
--    Level N unlocks only when Level N-1 is complete.
--    Enforced in the database, not the client.
-- =============================================================

create extension if not exists "pgcrypto";

create type user_role        as enum ('member','mentor','moderator','admin');
create type progress_status  as enum ('not_started','in_progress','completed');
create type reminder_channel as enum ('push','email','sms');
create type reminder_status  as enum ('queued','sent','failed','cancelled');
create type attend_method    as enum ('qr','manual','self');
create type block_type       as enum ('heading','text','scripture','image','video','question','reflection');

-- ---------- people ------------------------------------------

create table profiles (
  id             uuid primary key references auth.users on delete cascade,
  full_name      text not null,
  email          text,
  phone          text,                     -- E.164, e.g. +13055550123
  role           user_role not null default 'member',
  started_on     date,                     -- first Journey session attended
  pco_person_id  text unique,              -- Planning Center link
  pco_synced_at  timestamptz,
  sms_opt_in_at  timestamptz,              -- TCPA: null = never text
  email_opt_in   boolean not null default true,
  push_opt_in    boolean not null default true,
  is_minor       boolean not null default false,
  guardian_email text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on profiles (pco_person_id);

create table devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles on delete cascade,
  expo_token   text not null unique,
  platform     text not null check (platform in ('ios','android')),
  last_seen_at timestamptz not null default now()
);
create index on devices (user_id);

-- ---------- program content ---------------------------------
-- 4 rows. sabbath_of_month is which Saturday this level meets.

create table levels (
  id               uuid primary key default gen_random_uuid(),
  order_index      int not null unique check (order_index between 1 and 4),
  sabbath_of_month int not null unique check (sabbath_of_month between 1 and 4),
  title            text not null,
  subtitle         text,
  objective        text,
  memory_verse     text,
  memory_verse_ref text,
  homework         text,
  content_version  int not null default 1,   -- bump to invalidate client cache
  icon_url         text
);

-- Teaching material hangs directly off the level. No lessons table:
-- one level is one session, so there is nothing in between.
create table content_blocks (
  id          uuid primary key default gen_random_uuid(),
  level_id    uuid not null references levels on delete cascade,
  order_index int not null,
  type        block_type not null,
  body        text,
  media_url   text,
  meta        jsonb not null default '{}'::jsonb,
  unique (level_id, order_index)
);

-- ---------- the monthly calendar ----------------------------
-- One row per level per month. Level 1 gets 12 rows a year.

create table sessions (
  id           uuid primary key default gen_random_uuid(),
  level_id     uuid not null references levels on delete cascade,
  meets_on     date not null,             -- the actual Sabbath date
  starts_at    timestamptz not null,
  location     text,
  checkin_code text unique default encode(gen_random_bytes(8),'hex'),  -- QR payload
  notes        text,
  unique (level_id, meets_on)
);
create index on sessions (meets_on);
create index on sessions (starts_at);

create table attendance (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references sessions on delete cascade,
  user_id       uuid not null references profiles on delete cascade,
  method        attend_method not null default 'qr',
  checked_in_by uuid references profiles,
  checked_in_at timestamptz not null default now(),
  unique (session_id, user_id)
);
create index on attendance (user_id);

-- ---------- progress ----------------------------------------

create table level_progress (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles on delete cascade,
  level_id      uuid not null references levels on delete cascade,
  status        progress_status not null default 'not_started',
  last_block_id uuid references content_blocks,
  answers       jsonb not null default '{}'::jsonb,
  completed_at  timestamptz,
  client_uuid   uuid unique,              -- offline outbox idempotency key
  updated_at    timestamptz not null default now(),
  unique (user_id, level_id)
);
create index on level_progress (user_id, level_id);

-- Written by trigger once both gates pass. Never written by the client.
create table level_completions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles on delete cascade,
  level_id     uuid not null references levels on delete cascade,
  completed_at timestamptz not null default now(),
  unique (user_id, level_id)
);

-- ---------- reminders & ops ---------------------------------

create table reminders (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles on delete cascade,
  session_id uuid references sessions on delete cascade,
  channel    reminder_channel not null,
  send_at    timestamptz not null,
  status     reminder_status not null default 'queued',
  attempts   int not null default 0,
  last_error text,
  sent_at    timestamptz
);
create index on reminders (status, send_at);

create table pco_sync_log (
  id         bigserial primary key,
  user_id    uuid references profiles on delete set null,
  field      text,
  value      text,
  ok         boolean not null,
  response   text,
  at         timestamptz not null default now()
);
create index on pco_sync_log (user_id, at desc);

create table audit_log (
  id       bigserial primary key,
  actor_id uuid references profiles,
  action   text not null,
  target   text,
  detail   jsonb,
  at       timestamptz not null default now()
);

-- =============================================================
--  GATING LOGIC
-- =============================================================

-- Attended ANY monthly occurrence of this level. This is what
-- makes makeups work: September's Level 2 and October's Level 2
-- are equally valid.
create or replace function attended_level(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select exists (
    select 1
    from attendance a
    join sessions s on s.id = a.session_id
    where a.user_id = p_user
      and s.level_id = p_level
  );
$$;

create or replace function level_done(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select
    exists (
      select 1 from level_progress
      where user_id = p_user
        and level_id = p_level
        and status = 'completed'
    )
    and attended_level(p_user, p_level);
$$;

create or replace function can_access_level(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  with target as (select order_index from levels where id = p_level)
  select case
    when (select order_index from target) = 1 then true
    else exists (
      select 1 from levels prev
      where prev.order_index = (select order_index from target) - 1
        and level_done(p_user, prev.id)
    )
  end;
$$;

-- Which level is this person due for next? Drives the PCO field,
-- the reminder audience, and the app home screen. Returns NULL
-- when all four are finished.
create or replace function next_level_due(p_user uuid)
returns int language sql stable as $$
  select min(l.order_index)
  from levels l
  where not level_done(p_user, l.id);
$$;

-- The next calendar date they should show up, given where they are.
create or replace function next_session_for(p_user uuid)
returns uuid language sql stable as $$
  select s.id
  from sessions s
  join levels  l on l.id = s.level_id
  where l.order_index = next_level_due(p_user)
    and s.starts_at > now()
  order by s.starts_at
  limit 1;
$$;

create or replace function refresh_level_completion()
returns trigger language plpgsql security definer as $$
declare v_user uuid; v_level uuid;
begin
  if tg_table_name = 'level_progress' then
    v_user := new.user_id;  v_level := new.level_id;
  else
    v_user := new.user_id;
    v_level := (select level_id from sessions where id = new.session_id);
  end if;

  if level_done(v_user, v_level) then
    insert into level_completions (user_id, level_id)
    values (v_user, v_level)
    on conflict (user_id, level_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger trg_progress_completion
  after insert or update on level_progress
  for each row execute function refresh_level_completion();

create trigger trg_attendance_completion
  after insert on attendance
  for each row execute function refresh_level_completion();

-- =============================================================
--  ROW LEVEL SECURITY
-- =============================================================

create or replace function is_staff()
returns boolean language sql stable as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role in ('moderator','admin')
  );
$$;

alter table profiles          enable row level security;
alter table levels            enable row level security;
alter table content_blocks    enable row level security;
alter table level_progress    enable row level security;
alter table level_completions enable row level security;
alter table attendance        enable row level security;
alter table sessions          enable row level security;
alter table devices           enable row level security;

create policy own_profile on profiles
  for select using (id = auth.uid() or is_staff());
create policy edit_own_profile on profiles
  for update using (id = auth.uid());

-- Titles visible so members can see the road ahead...
create policy levels_readable on levels
  for select using (true);

-- ...but the teaching material itself stays locked.
create policy blocks_gated on content_blocks
  for select using (can_access_level(auth.uid(), level_id) or is_staff());

create policy own_progress on level_progress
  for select using (user_id = auth.uid() or is_staff());
create policy write_own_progress on level_progress
  for insert with check (user_id = auth.uid() and can_access_level(auth.uid(), level_id));
create policy update_own_progress on level_progress
  for update using (user_id = auth.uid() and can_access_level(auth.uid(), level_id));

create policy own_completions on level_completions
  for select using (user_id = auth.uid() or is_staff());

create policy read_attendance on attendance
  for select using (user_id = auth.uid() or is_staff());
create policy staff_marks_attendance on attendance
  for insert with check (is_staff());

create policy sessions_visible on sessions
  for select using (true);

create policy own_devices on devices
  for all using (user_id = auth.uid());

-- =============================================================
--  MODERATOR REPORTING
-- =============================================================

create materialized view mv_progress_report as
select
  p.id                       as user_id,
  p.full_name,
  p.email,
  p.phone,
  p.started_on,
  l.order_index              as level,
  l.title                    as level_title,
  coalesce(lp.status,'not_started')   as lesson_status,
  attended_level(p.id, l.id)          as attended,
  level_done(p.id, l.id)              as level_complete,
  lp.completed_at,
  next_level_due(p.id)                as next_level
from profiles p
cross join levels l
left join level_progress lp on lp.user_id = p.id and lp.level_id = l.id
where p.role = 'member';

create unique index on mv_progress_report (user_id, level);

select cron.schedule('refresh-report','*/10 * * * *',
  $$refresh materialized view concurrently mv_progress_report$$);

-- =============================================================
--  CALENDAR GENERATOR
--  Builds a year of Sabbaths: level N on the Nth Saturday.
--  Run once a year, or extend the range as needed.
-- =============================================================

create or replace function generate_journey_calendar(
  p_from date,
  p_months int,
  p_start_time time default '10:00',
  p_location text default 'Arise Miami SDA Church'
) returns int language plpgsql as $$
declare
  m date; n int; d date; made int := 0; v_level uuid;
begin
  for i in 0 .. p_months - 1 loop
    m := date_trunc('month', p_from)::date + (i || ' months')::interval;
    for n in 1 .. 4 loop
      -- nth Saturday of month m
      d := m + ((6 - extract(dow from m)::int + 7) % 7)
             + ((n - 1) * 7);
      if extract(month from d) = extract(month from m) then
        select id into v_level from levels where sabbath_of_month = n;
        insert into sessions (level_id, meets_on, starts_at, location)
        values (v_level, d, (d + p_start_time) at time zone 'America/New_York', p_location)
        on conflict (level_id, meets_on) do nothing;
        made := made + 1;
      end if;
    end loop;
  end loop;
  return made;
end;
$$;

-- =============================================================
--  SEED
-- =============================================================

insert into levels (order_index, sabbath_of_month, title) values
  (1,1,'Level 1'), (2,2,'Level 2'), (3,3,'Level 3'), (4,4,'Level 4')
on conflict do nothing;

-- Generate 12 months of Sabbaths starting next month:
-- select generate_journey_calendar(date_trunc('month', now())::date, 12);
