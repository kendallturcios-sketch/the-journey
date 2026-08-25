-- =============================================================
--  THE JOURNEY · migration 003
--  Three content models, one per shape of level.
--
--    L1, L2  fill-in-the-blank, one correct answer per blank
--    L3      personal reflection, no correct answers
--    L4      covenant — terms disclosed, signed symbolically
--
--  Completion is therefore level-specific: correct blanks,
--  written reflections, or a signature.
-- =============================================================

alter type block_type add value if not exists 'fill_blank';
alter type block_type add value if not exists 'reflection_prompt';
alter type block_type add value if not exists 'covenant';

-- ---------- Levels 1 & 2 · worksheets -----------------------
-- The block's meta holds the blanks:
--   { "blanks": [ { "accepts": ["death"] },
--                 { "accepts": ["eternal","everlasting"] } ] }

create table worksheet_answers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles on delete cascade,
  block_id    uuid not null references content_blocks on delete cascade,
  blank_index int  not null,
  value       text not null,
  is_correct  boolean not null default false,
  attempts    int not null default 1,
  revealed    boolean not null default false,   -- shown after 3 tries
  answered_at timestamptz not null default now(),
  client_uuid uuid unique,                      -- offline outbox key
  unique (user_id, block_id, blank_index)
);
create index on worksheet_answers (user_id);

-- ---------- Level 3 · reflections ---------------------------
-- Separate table so a reporting query cannot reach this text
-- by accident. Visibility is ONE policy below — flip it if the
-- pastoral call changes.

create table reflections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles on delete cascade,
  block_id   uuid not null references content_blocks on delete cascade,
  body       text not null default '',
  updated_at timestamptz not null default now(),
  unique (user_id, block_id)
);
create index on reflections (user_id);

-- ---------- Level 4 · covenant ------------------------------
-- Versioned and immutable. If Arise revises the terms, a NEW
-- row is added — never edit an existing one. Otherwise you
-- cannot answer "what exactly did she agree to in 2026?"

create table covenant_versions (
  id            uuid primary key default gen_random_uuid(),
  version       int not null unique,
  title         text not null,
  body          text not null,          -- the terms, in full
  effective_on  date not null,
  retired_on    date,
  created_at    timestamptz not null default now()
);

create table covenant_signatures (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles on delete cascade,
  covenant_id   uuid not null references covenant_versions,
  signature_url text,                   -- drawn signature, Supabase Storage
  typed_name    text,                   -- fallback if they'd rather type
  signed_at     timestamptz not null default now(),
  session_id    uuid references sessions,
  unique (user_id, covenant_id)
);
create index on covenant_signatures (user_id);

-- Signatures are a record of commitment, not a draft. Once made,
-- the app cannot alter or remove one.
create or replace function block_signature_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'Covenant signatures are immutable';
end;
$$;

create trigger trg_signature_immutable
  before update or delete on covenant_signatures
  for each row execute function block_signature_mutation();

-- =============================================================
--  LEVEL-SPECIFIC COMPLETION
-- =============================================================

-- Every fill_blank on this level answered correctly or revealed.
create or replace function worksheet_done(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  with blanks as (
    select cb.id as block_id,
           generate_series(0, jsonb_array_length(cb.meta->'blanks') - 1) as idx
    from content_blocks cb
    where cb.level_id = p_level and cb.type = 'fill_blank'
  )
  select not exists (
    select 1 from blanks b
    left join worksheet_answers wa
      on wa.user_id = p_user
     and wa.block_id = b.block_id
     and wa.blank_index = b.idx
    where wa.id is null or not (wa.is_correct or wa.revealed)
  );
$$;

-- Every reflection prompt has something written in it.
create or replace function reflections_done(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select not exists (
    select 1 from content_blocks cb
    left join reflections r
      on r.user_id = p_user and r.block_id = cb.id
    where cb.level_id = p_level
      and cb.type = 'reflection_prompt'
      and (r.id is null or length(btrim(r.body)) = 0)
  );
$$;

create or replace function covenant_done(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select case
    when not exists (
      select 1 from content_blocks
      where level_id = p_level and type = 'covenant'
    ) then true
    else exists (select 1 from covenant_signatures where user_id = p_user)
  end;
$$;

-- The lesson half of the gate. Whatever this level contains,
-- all of it must be satisfied.
create or replace function lesson_requirements_met(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select worksheet_done(p_user, p_level)
     and reflections_done(p_user, p_level)
     and covenant_done(p_user, p_level);
$$;

-- Attendance AND lesson, as always — but the lesson half is now
-- computed from actual work rather than a self-marked flag.
create or replace function level_done(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select attended_level(p_user, p_level)
     and lesson_requirements_met(p_user, p_level);
$$;

-- =============================================================
--  ROW LEVEL SECURITY
-- =============================================================

alter table worksheet_answers    enable row level security;
alter table reflections          enable row level security;
alter table covenant_versions    enable row level security;
alter table covenant_signatures  enable row level security;

create policy own_worksheet on worksheet_answers
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid() and can_access_level(
    auth.uid(), (select level_id from content_blocks where id = block_id)));

create policy staff_read_worksheet on worksheet_answers
  for select using (is_staff());

-- Level 3 reflections: participants are told up front that
-- Journey staff may read these. Drop this one policy to make
-- them owner-only; nothing else in the app depends on it.
create policy own_reflections on reflections
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy staff_read_reflections on reflections
  for select using (is_staff());

create policy covenant_readable on covenant_versions
  for select using (true);

create policy own_signature on covenant_signatures
  for select using (user_id = auth.uid() or is_staff());
create policy sign_own on covenant_signatures
  for insert with check (user_id = auth.uid()
    and can_access_level(auth.uid(),
      (select id from levels where order_index = 4)));

-- =============================================================
--  JOURNEY COMPLETION
-- =============================================================

create or replace function journey_finished_at(p_user uuid)
returns timestamptz language sql stable as $$
  select max(completed_at)
  from level_completions
  where user_id = p_user
  having count(*) = 4;
$$;
