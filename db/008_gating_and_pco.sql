-- =============================================================
--  THE JOURNEY · migration 008
--
--  Two changes:
--   1. Unlocking runs on WORK DONE, not on attendance.
--      Attendance is still recorded — it just stops being a wall.
--   2. Progress pushes back to Planning Center so Arise can see
--      who has completed what without opening this app.
-- =============================================================

-- ---------- settings you can flip without a deploy ----------

create table program_settings (
  id                      boolean primary key default true check (id),
  gate_on_attendance      boolean not null default false,  -- L3 door
  gate_l4_on_attendance   boolean not null default true,   -- covenant door
  require_gifts_for_l3    boolean not null default true,
  updated_at              timestamptz not null default now()
);
insert into program_settings default values on conflict do nothing;

-- ---------- the doors ---------------------------------------

-- Did they do Level N's actual work? (blanks / reflections / covenant)
create or replace function work_done(p_user uuid, p_order int)
returns boolean language sql stable as $$
  select lesson_requirements_met(p_user,
           (select id from levels where order_index = p_order));
$$;

-- Satisfied Level N — by work, and by attendance only if configured.
create or replace function cleared(p_user uuid, p_order int, p_strict boolean)
returns boolean language sql stable as $$
  select work_done(p_user, p_order)
     and (not p_strict or attended_order(p_user, p_order));
$$;

create or replace function can_access_level(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  with s as (select * from program_settings limit 1)
  select case (select order_index from levels where id = p_level)
    when 1 then true
    when 2 then true
    when 3 then cleared(p_user, 2, (select gate_on_attendance from s))
                and (not (select require_gifts_for_l3 from s)
                     or has_spiritual_gifts(p_user))
    when 4 then cleared(p_user, 3, (select gate_l4_on_attendance from s))
    else false
  end;
$$;

-- Certification is unchanged and still strict: to have COMPLETED
-- The Journey you must have been in the room for all four.
-- level_done() keeps requiring attendance AND the work.

create or replace function level_status(p_user uuid)
returns table (level int, title text, unlocked boolean, attended boolean,
               work boolean, complete boolean, blocked_by text)
language sql stable as $$
  with s as (select * from program_settings limit 1)
  select l.order_index, l.title,
         can_access_level(p_user, l.id),
         attended_level(p_user, l.id),
         work_done(p_user, l.order_index),
         level_done(p_user, l.id),
         case
           when can_access_level(p_user, l.id) then null
           when l.order_index = 3 and not work_done(p_user, 2)
             then 'Finish the Level 2 lesson'
           when l.order_index = 3 and (select gate_on_attendance from s)
                and not attended_order(p_user, 2)
             then 'Attend Level 2'
           when l.order_index = 3 and not has_spiritual_gifts(p_user)
             then 'Complete the spiritual gifts survey'
           when l.order_index = 4 and not work_done(p_user, 3)
             then 'Finish the Level 3 reflection'
           when l.order_index = 4 then 'Attend Level 3'
         end
  from levels l order by l.order_index;
$$;

-- =============================================================
--  PUSH TO PLANNING CENTER
--  One row per person per change. An Edge Function drains this
--  queue and PATCHes the PCO field. Retries live here so a
--  failed push is visible instead of silent.
-- =============================================================

create table pco_outbox (
  id          bigserial primary key,
  user_id     uuid not null references profiles on delete cascade,
  field       text not null,          -- 'Journey Progress', 'Journey Completed'
  value       text not null,
  status      text not null default 'queued',  -- queued|sent|failed
  attempts    int  not null default 0,
  last_error  text,
  queued_at   timestamptz not null default now(),
  sent_at     timestamptz
);
create index on pco_outbox (status, queued_at);

-- "L1, L2 complete · next: Level 3" — readable inside PCO.
create or replace function journey_summary(p_user uuid)
returns text language sql stable as $$
  with d as (
    select l.order_index as n, level_done(p_user, l.id) as done
    from levels l
  )
  select case
    when (select bool_and(done) from d) then 'Journey complete'
    when not exists (select 1 from d where done) then 'Not started'
    else 'Completed: ' ||
         (select string_agg('L'||n, ', ' order by n) from d where done) ||
         ' · Still needs: ' ||
         (select string_agg('L'||n, ', ' order by n) from d where not done)
  end;
$$;

create or replace function queue_pco_push()
returns trigger language plpgsql security definer as $$
declare v_user uuid;
begin
  v_user := new.user_id;

  insert into pco_outbox (user_id, field, value)
  values (v_user, 'Journey Progress', journey_summary(v_user));

  if journey_complete(v_user) then
    insert into pco_outbox (user_id, field, value)
    values (v_user, 'Journey Completed', to_char(now(), 'YYYY-MM-DD'));
  end if;

  return new;
end;
$$;

create trigger trg_pco_on_completion
  after insert on level_completions
  for each row execute function queue_pco_push();

create trigger trg_pco_on_attendance
  after insert on attendance
  for each row execute function queue_pco_push();

-- What a leader actually wants to look at.
create or replace view v_journey_roster as
select p.full_name, p.email, p.phone, p.started_on,
       level_done(p.id,(select id from levels where order_index=1)) as l1,
       level_done(p.id,(select id from levels where order_index=2)) as l2,
       level_done(p.id,(select id from levels where order_index=3)) as l3,
       level_done(p.id,(select id from levels where order_index=4)) as l4,
       has_spiritual_gifts(p.id)  as gifts_survey,
       journey_complete(p.id)     as finished,
       p.pco_person_id
from profiles p
where p.role = 'member'
order by p.full_name;

alter table program_settings enable row level security;
create policy settings_read on program_settings for select using (true);
create policy settings_write on program_settings for update using (is_staff());
