-- =============================================================
--  THE JOURNEY · migration 004
--  Spiritual gifts survey — homework between Level 2 and Level 3.
--
--  External survey: https://gifts.churchgrowth.org/spiritual-gifts-survey
--  No API, so the participant records their own top three from
--  the fixed list of nine. Tap, don't type.
-- =============================================================

create type spiritual_gift as enum (
  'evangelism','prophecy','teaching','exhortation','shepherding',
  'serving','mercy_showing','giving','administration'
);

create table spiritual_gifts_results (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles on delete cascade,
  gift_1          spiritual_gift not null,
  gift_2          spiritual_gift not null,
  gift_3          spiritual_gift not null,
  survey_taken_on date,
  proof_url       text,            -- optional screenshot of results page
  recorded_at     timestamptz not null default now(),
  unique (user_id),
  check (gift_1 <> gift_2 and gift_2 <> gift_3 and gift_1 <> gift_3)
);

-- Pastoral escape hatch. A leader can seat someone who did the
-- work but can't produce it, without loosening the rule itself.
alter table profiles
  add column gifts_waived_by uuid references profiles,
  add column gifts_waived_at timestamptz;

create or replace function has_spiritual_gifts(p_user uuid)
returns boolean language sql stable as $$
  select exists (select 1 from spiritual_gifts_results where user_id = p_user)
      or exists (select 1 from profiles
                 where id = p_user and gifts_waived_at is not null);
$$;

-- Level 3 now needs a foundation level AND the survey done.
create or replace function can_access_level(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select case (select order_index from levels where id = p_level)
    when 1 then true
    when 2 then true
    when 3 then (attended_order(p_user, 1) or attended_order(p_user, 2))
                and has_spiritual_gifts(p_user)
    when 4 then attended_order(p_user, 3)
    else false
  end;
$$;

-- Who to nudge before the third Sabbath: eligible on every other
-- count, but the survey is missing.
create or replace function needs_gifts_survey()
returns table (user_id uuid, full_name text, email text, phone text)
language sql stable as $$
  select p.id, p.full_name, p.email, p.phone
  from profiles p
  where p.role = 'member'
    and (attended_order(p.id, 1) or attended_order(p.id, 2))
    and not has_spiritual_gifts(p.id)
    and not exists (
      select 1 from levels l
      where l.order_index = 3 and level_done(p.id, l.id)
    );
$$;

alter table spiritual_gifts_results enable row level security;

create policy own_gifts on spiritual_gifts_results
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy staff_read_gifts on spiritual_gifts_results
  for select using (is_staff());
