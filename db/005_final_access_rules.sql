-- =============================================================
--  THE JOURNEY · migration 005
--  Final access rules.
--
--      2 ──→ 3 ──→ 4
--      1   floats — any time, before or after anything
--
--    L1  always open
--    L2  always open
--    L3  attended L2  AND  spiritual gifts survey recorded
--    L4  attended L3
--
--  Level 4 deliberately does NOT require Level 1. Someone can
--  sign the covenant and come back for Level 1 later; maximum
--  flexibility was the call.
-- =============================================================

create or replace function can_access_level(p_user uuid, p_level uuid)
returns boolean language sql stable as $$
  select case (select order_index from levels where id = p_level)
    when 1 then true
    when 2 then true
    when 3 then attended_order(p_user, 2) and has_spiritual_gifts(p_user)
    when 4 then attended_order(p_user, 3)
    else false
  end;
$$;

-- Nudge audience: sat through Level 2, survey still not recorded.
-- Everyone here heard the assignment given in the room.
create or replace function needs_gifts_survey()
returns table (user_id uuid, full_name text, email text, phone text)
language sql stable as $$
  select p.id, p.full_name, p.email, p.phone
  from profiles p
  where p.role = 'member'
    and attended_order(p.id, 2)
    and not has_spiritual_gifts(p.id);
$$;

-- Handy for the app home screen and the moderator dashboard:
-- what can this person do right now, and why not?
create or replace function level_status(p_user uuid)
returns table (
  level      int,
  title      text,
  unlocked   boolean,
  attended   boolean,
  complete   boolean,
  blocked_by text
) language sql stable as $$
  select
    l.order_index,
    l.title,
    can_access_level(p_user, l.id),
    attended_level(p_user, l.id),
    level_done(p_user, l.id),
    case
      when can_access_level(p_user, l.id) then null
      when l.order_index = 3 and not attended_order(p_user, 2)
        then 'Attend Level 2 first'
      when l.order_index = 3 and not has_spiritual_gifts(p_user)
        then 'Complete the spiritual gifts survey'
      when l.order_index = 4
        then 'Attend Level 3 first'
    end
  from levels l
  order by l.order_index;
$$;
