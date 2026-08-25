-- =============================================================
--  THE JOURNEY · migration 007
--  Ministry rollout at Level 4, and the handoff to leaders.
--
--  The problem this solves: people finish The Journey and never
--  land anywhere. So an expressed interest is not a message —
--  it is an open item with an owner, a state, and a clock.
--  Nothing closes without a leader saying what happened.
-- =============================================================

create type handoff_status as enum (
  'expressed',      -- participant picked it; leader notified
  'acknowledged',   -- leader has seen it
  'contacted',      -- leader has actually reached out
  'serving',        -- they're in. the point of all this.
  'declined',       -- person decided against it
  'unreachable'     -- leader tried, no response
);

create table ministries (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  blurb       text,                        -- one line, shown on the card
  description text,                        -- fuller copy
  suits_gifts spiritual_gift[] not null default '{}',
  meets_when  text,                        -- "Sabbath afternoons"
  image_url   text,
  is_active   boolean not null default true,
  sort_order  int not null default 100
);

create table ministry_leaders (
  ministry_id uuid not null references ministries on delete cascade,
  user_id     uuid not null references profiles on delete cascade,
  is_primary  boolean not null default false,
  primary key (ministry_id, user_id)
);
create index on ministry_leaders (user_id);

create table ministry_interests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles on delete cascade,
  ministry_id   uuid not null references ministries on delete cascade,
  status        handoff_status not null default 'expressed',
  expressed_at  timestamptz not null default now(),
  claimed_by    uuid references profiles,      -- which leader owns it
  acknowledged_at timestamptz,
  contacted_at  timestamptz,
  closed_at     timestamptz,
  outcome_note  text,
  escalated_at  timestamptz,
  unique (user_id, ministry_id)
);
create index on ministry_interests (ministry_id, status);
create index on ministry_interests (status, expressed_at);

-- ---------- gift-based suggestions ---------------------------

create or replace function suggested_ministries(p_user uuid)
returns table (ministry_id uuid, name text, blurb text, matched spiritual_gift[])
language sql stable as $$
  with g as (
    select array[gift_1, gift_2, gift_3] as gifts
    from spiritual_gifts_results where user_id = p_user
  )
  select m.id, m.name, m.blurb,
         array(select unnest(m.suits_gifts) intersect select unnest(g.gifts))
  from ministries m, g
  where m.is_active
    and m.suits_gifts && g.gifts
  order by cardinality(
    array(select unnest(m.suits_gifts) intersect select unnest(g.gifts))
  ) desc, m.sort_order;
$$;

-- ---------- notify the leaders, immediately ------------------

create or replace function notify_ministry_leaders()
returns trigger language plpgsql security definer as $$
begin
  insert into reminders (user_id, channel, send_at, status)
  select ml.user_id, 'email', now(), 'queued'
  from ministry_leaders ml
  where ml.ministry_id = new.ministry_id;

  insert into reminders (user_id, channel, send_at, status)
  select ml.user_id, 'push', now(), 'queued'
  from ministry_leaders ml
  join devices d on d.user_id = ml.user_id
  where ml.ministry_id = new.ministry_id;

  return new;
end;
$$;

create trigger trg_notify_ministry
  after insert on ministry_interests
  for each row execute function notify_ministry_leaders();

-- ---------- the clock ----------------------------------------
-- Nudge the leader at 3 days. Escalate at 7. This is the part
-- that actually prevents people falling through.

create or replace function stale_handoffs(p_days int default 3)
returns table (
  interest_id  uuid,
  person       text,
  ministry     text,
  status       handoff_status,
  days_open    int,
  leader_ids   uuid[]
) language sql stable as $$
  select mi.id,
         p.full_name,
         m.name,
         mi.status,
         extract(day from now() - mi.expressed_at)::int,
         array(select user_id from ministry_leaders where ministry_id = m.id)
  from ministry_interests mi
  join profiles   p on p.id = mi.user_id
  join ministries m on m.id = mi.ministry_id
  where mi.status in ('expressed','acknowledged')
    and mi.expressed_at < now() - (p_days || ' days')::interval
  order by mi.expressed_at;
$$;

-- Runs nightly. Nudges leaders, then escalates to moderators.
create or replace function process_handoff_escalations()
returns int language plpgsql security definer as $$
declare r record; n int := 0;
begin
  -- 3 days: remind the leaders
  for r in select * from stale_handoffs(3) loop
    insert into reminders (user_id, channel, send_at, status)
    select unnest(r.leader_ids), 'email', now(), 'queued';
    n := n + 1;
  end loop;

  -- 7 days: put it in front of the moderators, once
  for r in select * from stale_handoffs(7) loop
    if not exists (select 1 from ministry_interests
                   where id = r.interest_id and escalated_at is not null) then
      insert into reminders (user_id, channel, send_at, status)
      select id, 'email', now(), 'queued'
      from profiles where role in ('moderator','admin');

      update ministry_interests
      set escalated_at = now() where id = r.interest_id;
    end if;
  end loop;

  return n;
end;
$$;

select cron.schedule('handoff-escalations','0 13 * * *',
  $$select process_handoff_escalations()$$);

-- ---------- the dashboard view -------------------------------

create or replace view v_open_handoffs as
select mi.id,
       p.full_name           as person,
       p.email               as person_email,
       p.phone               as person_phone,
       m.name                as ministry,
       mi.status,
       mi.expressed_at,
       extract(day from now() - mi.expressed_at)::int as days_open,
       mi.escalated_at is not null                    as escalated,
       lp.full_name          as claimed_by
from ministry_interests mi
join profiles   p  on p.id = mi.user_id
join ministries m  on m.id = mi.ministry_id
left join profiles lp on lp.id = mi.claimed_by
where mi.status not in ('serving','declined')
order by mi.expressed_at;

-- ---------- RLS ----------------------------------------------

alter table ministries          enable row level security;
alter table ministry_leaders    enable row level security;
alter table ministry_interests  enable row level security;

create policy ministries_readable on ministries
  for select using (is_active or is_staff());

create policy leaders_readable on ministry_leaders
  for select using (true);

-- A leader sees only their own ministry's people.
create policy own_or_led_interests on ministry_interests
  for select using (
    user_id = auth.uid()
    or is_staff()
    or exists (select 1 from ministry_leaders
               where ministry_id = ministry_interests.ministry_id
                 and user_id = auth.uid())
  );

create policy express_interest on ministry_interests
  for insert with check (
    user_id = auth.uid()
    and can_access_level(auth.uid(),
        (select id from levels where order_index = 4))
  );

-- Only the ministry's leaders (or staff) can move it along.
create policy leaders_update_status on ministry_interests
  for update using (
    is_staff()
    or exists (select 1 from ministry_leaders
               where ministry_id = ministry_interests.ministry_id
                 and user_id = auth.uid())
  );
