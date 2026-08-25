-- =============================================================
--  THE JOURNEY · migration 009
--  Bring in the ~100 people already tracked through the
--  Church Center forms (Level 1 form = 480411).
--
--  These people attended real sessions but never filled in an
--  in-app worksheet — that didn't exist. So a legacy completion
--  has to satisfy the gate on its own.
-- =============================================================

alter table level_completions
  add column source        text not null default 'app'
    check (source in ('app','legacy')),
  add column legacy_ref    text,        -- Church Center submission id
  add column legacy_note   text;

create index on level_completions (source);

-- Where each level's Church Center form lives, so the importer
-- knows which form maps to which level.
create table legacy_forms (
  level_order int primary key check (level_order between 1 and 4),
  form_id     text not null,
  form_url    text,
  imported_at timestamptz
);

insert into legacy_forms (level_order, form_id, form_url) values
  (1,'480411','https://arisemiami.churchcenter.com/people/forms/480411')
on conflict do nothing;
-- Levels 2-4 form ids get added once their QR codes are decoded.

-- ---------- the gate, with history honoured ------------------

create or replace function has_legacy(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from level_completions
    where user_id = p_user and level_id = p_level and source = 'legacy'
  );
$$;

-- A legacy row stands in for both halves of the gate.
create or replace function level_done(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select has_legacy(p_user, p_level)
      or (attended_level(p_user, p_level)
          and lesson_requirements_met(p_user, p_level));
$$;

create or replace function work_done(p_user uuid, p_order int)
returns boolean language sql stable as $$
  with l as (select id from levels where order_index = p_order)
  select has_legacy(p_user, (select id from l))
      or lesson_requirements_met(p_user, (select id from l));
$$;

create or replace function attended_order(p_user uuid, p_order int)
returns boolean language sql stable as $$
  with l as (select id from levels where order_index = p_order)
  select has_legacy(p_user, (select id from l))
      or exists (
        select 1 from attendance a
        join sessions s on s.id = a.session_id
        where a.user_id = p_user and s.level_id = (select id from l)
      );
$$;

-- ---------- staging, so a bad import can be undone -----------

create table legacy_import_staging (
  id             bigserial primary key,
  form_id        text,
  submission_id  text unique,
  level_order    int,
  full_name      text,
  email          text,
  phone          text,
  submitted_at   timestamptz,
  pco_person_id  text,
  matched_user   uuid references profiles,
  match_method   text,        -- pco_id | email | phone | name | unmatched
  raw            jsonb,
  promoted       boolean not null default false
);

-- Match a staged submission to a person: PCO id, then email, then phone.
-- Deliberately does NOT match on name alone — two Maria Rodriguezes in
-- one congregation is not a hypothetical.
create or replace function match_legacy_rows()
returns int language plpgsql as $$
declare r record; n int := 0; v uuid; m text;
begin
  for r in select * from legacy_import_staging where matched_user is null loop
    v := null; m := 'unmatched';

    if r.pco_person_id is not null then
      select id into v from profiles where pco_person_id = r.pco_person_id;
      if v is not null then m := 'pco_id'; end if;
    end if;

    if v is null and r.email is not null then
      select id into v from profiles where lower(email) = lower(r.email);
      if v is not null then m := 'email'; end if;
    end if;

    if v is null and r.phone is not null then
      select id into v from profiles
      where regexp_replace(phone,'\D','','g') = regexp_replace(r.phone,'\D','','g');
      if v is not null then m := 'phone'; end if;
    end if;

    update legacy_import_staging
    set matched_user = v, match_method = m where id = r.id;
    if v is not null then n := n + 1; end if;
  end loop;
  return n;
end;
$$;

-- Promote matched rows into real completions. Review first.
create or replace function promote_legacy()
returns int language plpgsql as $$
declare n int;
begin
  with ins as (
    insert into level_completions
      (user_id, level_id, completed_at, source, legacy_ref, legacy_note)
    select s.matched_user,
           l.id,
           coalesce(s.submitted_at, now()),
           'legacy',
           s.submission_id,
           'Imported from Church Center form ' || s.form_id
    from legacy_import_staging s
    join levels l on l.order_index = s.level_order
    where s.matched_user is not null and not s.promoted
    on conflict (user_id, level_id) do nothing
    returning 1
  )
  select count(*) into n from ins;

  update legacy_import_staging
  set promoted = true where matched_user is not null;
  return n;
end;
$$;

-- ---------- what you've never been able to see --------------

create or replace view v_journey_funnel as
with m as (select id from profiles where role = 'member')
select l.order_index                       as level,
       l.title,
       count(*) filter (where level_done(m.id, l.id)) as completed,
       round(100.0 * count(*) filter (where level_done(m.id, l.id))
             / nullif(count(*),0), 1)      as pct_of_all
from levels l cross join m
group by l.order_index, l.title
order by l.order_index;

-- Everyone who started and stopped — the re-engagement list.
create or replace view v_stalled as
select p.full_name, p.email, p.phone,
       levels_outstanding(p.id)  as still_needs,
       (select max(completed_at) from level_completions
         where user_id = p.id)   as last_activity
from profiles p
where p.role = 'member'
  and not journey_complete(p.id)
  and exists (select 1 from level_completions where user_id = p.id)
order by last_activity desc nulls last;
