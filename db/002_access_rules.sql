-- =============================================================
--  THE JOURNEY · migration 002
--  Replaces strict sequential gating with the real rules.
--
--  ACCESS (can you open the content?) — based on ATTENDANCE.
--    L1  always
--    L2  always
--    L3  attended L1 OR attended L2
--    L4  attended L3
--
--  COMPLETION (have you finished The Journey?) — stricter.
--    Every level needs attendance AND the in-app lesson.
--
--  Two different bars on purpose. Someone sitting in the room
--  must never find their phone locked mid-teaching.
-- =============================================================

create or replace function attended_order(p_user uuid, p_order int)
returns boolean language sql stable as $$
  select exists (
    select 1
    from attendance a
    join sessions s on s.id = a.session_id
    join levels   l on l.id = s.level_id
    where a.user_id = p_user
      and l.order_index = p_order
  );
$$;

create or replace function can_access_level(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select case (select order_index from levels where id = p_level)
    when 1 then true
    when 2 then true
    when 3 then attended_order(p_user, 1) or attended_order(p_user, 2)
    when 4 then attended_order(p_user, 3)
    else false
  end;
$$;

-- Check-in opens the door. Staff scan the QR, and that person's
-- content for this level is live before the teaching starts.
create or replace function unlock_on_checkin()
returns trigger language plpgsql security definer as $$
declare v_level uuid;
begin
  v_level := (select level_id from sessions where id = new.session_id);
  insert into level_progress (user_id, level_id, status)
  values (new.user_id, v_level, 'in_progress')
  on conflict (user_id, level_id) do update
    set status = case when level_progress.status = 'not_started'
                      then 'in_progress' else level_progress.status end,
        updated_at = now();
  return new;
end;
$$;

create trigger trg_checkin_unlock
  after insert on attendance
  for each row execute function unlock_on_checkin();

-- Progress is no longer a line — someone can owe L2 while
-- having finished L4. Four independent flags, not one pointer.
create or replace function levels_outstanding(p_user uuid)
returns int[] language sql stable as $$
  select coalesce(array_agg(l.order_index order by l.order_index), '{}')
  from levels l
  where not level_done(p_user, l.id);
$$;

create or replace function journey_complete(p_user uuid)
returns boolean language sql stable as $$
  select cardinality(levels_outstanding(p_user)) = 0;
$$;

drop function if exists next_level_due(uuid);
drop function if exists next_session_for(uuid);

-- Who should be texted about an upcoming session: people who
-- still owe that level AND are allowed to sit in it.
create or replace function eligible_for_session(p_session uuid)
returns table (user_id uuid, full_name text, email text, phone text)
language sql stable as $$
  select p.id, p.full_name, p.email, p.phone
  from profiles p
  join sessions s on s.id = p_session
  where p.role = 'member'
    and not level_done(p.id, s.level_id)
    and can_access_level(p.id, s.level_id);
$$;

drop materialized view if exists mv_progress_report;

create materialized view mv_progress_report as
select
  p.id                     as user_id,
  p.full_name,
  p.email,
  p.phone,
  p.started_on,
  l.order_index            as level,
  l.title                  as level_title,
  coalesce(lp.status,'not_started') as lesson_status,
  attended_level(p.id, l.id)        as attended,
  level_done(p.id, l.id)            as level_complete,
  can_access_level(p.id, l.id)      as unlocked,
  lp.completed_at,
  levels_outstanding(p.id)          as still_owes,
  journey_complete(p.id)            as finished
from profiles p
cross join levels l
left join level_progress lp on lp.user_id = p.id and lp.level_id = l.id
where p.role = 'member';

create unique index on mv_progress_report (user_id, level);
