-- =============================================================
--  THE JOURNEY · migration 017
--  Baptism decisions at the end of Level 1.
--
--  Separate from the Level 4 ministry handoff on purpose. This
--  is not a serving choice — it is a response to the gospel, it
--  happens two months earlier, and it goes to the pastor first.
-- =============================================================

create type next_step_kind    as enum ('baptism','baby_dedication','conversation');
create type next_step_status  as enum (
  'expressed',     -- they said yes in the app; pastor notified
  'pastor_aware',  -- pastor has seen it
  'in_prep',       -- handed to the baptismal prep team
  'scheduled',     -- there is a date
  'completed',
  'not_now'        -- they changed their mind. recorded, not hidden.
);

create table next_step_decisions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles on delete cascade,
  kind          next_step_kind not null,
  status        next_step_status not null default 'expressed',
  expressed_at  timestamptz not null default now(),
  level_id      uuid references levels,          -- where they decided
  pastor_seen_at timestamptz,
  handed_off_at timestamptz,
  handed_to     uuid references profiles,
  scheduled_for date,
  completed_on  date,
  note          text,
  escalated_at  timestamptz,
  unique (user_id, kind, expressed_at)
);
create index on next_step_decisions (status, expressed_at);
create index on next_step_decisions (user_id);

-- Who hears about it, in order. Pastor first, always.
create table next_step_routing (
  kind        next_step_kind primary key,
  pastor_id   uuid references profiles,
  pastor_email text not null,
  team_name   text,
  escalate_after_days int not null default 2
);

insert into next_step_routing (kind, pastor_email, team_name, escalate_after_days) values
  ('baptism',        'PASTOR_EMAIL', 'Baptismal Prep Team', 2),
  ('baby_dedication','PASTOR_EMAIL', 'Baptismal Prep Team', 5),
  ('conversation',   'PASTOR_EMAIL', null, 3)
on conflict (kind) do nothing;

-- ---------- notify ------------------------------------------

create or replace function notify_next_step()
returns trigger language plpgsql security definer as $$
declare r record;
begin
  select * into r from next_step_routing where kind = new.kind;

  -- Pastor, by every channel he has.
  insert into reminders (user_id, channel, send_at, status)
  select p.id, c.ch::reminder_channel, now(), 'queued'
  from profiles p
  cross join (values ('email'),('push')) as c(ch)
  where lower(p.email) = lower(r.pastor_email);

  -- Moderators see it on the dashboard immediately.
  insert into audit_log (actor_id, action, target, detail)
  values (new.user_id, 'next_step_expressed', new.kind::text,
          jsonb_build_object('decision_id', new.id));

  return new;
end;
$$;

create trigger trg_notify_next_step
  after insert on next_step_decisions
  for each row execute function notify_next_step();

-- A baptism decision going unanswered is the worst failure in
-- this whole app. Two days, then it escalates to every moderator.
create or replace function escalate_next_steps()
returns int language plpgsql security definer as $$
declare d record; n int := 0;
begin
  for d in
    select nd.*, r.escalate_after_days
    from next_step_decisions nd
    join next_step_routing r on r.kind = nd.kind
    where nd.status = 'expressed'
      and nd.escalated_at is null
      and nd.expressed_at < now() - (r.escalate_after_days || ' days')::interval
  loop
    insert into reminders (user_id, channel, send_at, status)
    select id, 'email', now(), 'queued'
    from profiles where role in ('moderator','admin');

    update next_step_decisions set escalated_at = now() where id = d.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

select cron.schedule('next-step-escalations','0 14 * * *',
  $$select escalate_next_steps()$$);

-- ---------- what the pastor opens ---------------------------

create or replace view v_next_steps as
select nd.id,
       p.full_name,
       p.email,
       p.phone,
       nd.kind,
       nd.status,
       nd.expressed_at::date            as decided_on,
       extract(day from now() - nd.expressed_at)::int as days_open,
       nd.escalated_at is not null      as escalated,
       nd.scheduled_for,
       h.full_name                      as handed_to,
       nd.note
from next_step_decisions nd
join profiles p on p.id = nd.user_id
left join profiles h on h.id = nd.handed_to
where nd.status not in ('completed','not_now')
order by nd.expressed_at;

-- Hand it to the prep team, recording who now owns it.
create or replace function hand_off_next_step(p_id uuid, p_to uuid, p_note text default null)
returns void language sql security definer as $$
  update next_step_decisions
  set status = 'in_prep', handed_off_at = now(), handed_to = p_to,
      note = coalesce(p_note, note),
      pastor_seen_at = coalesce(pastor_seen_at, now())
  where id = p_id;
$$;

-- ---------- RLS ---------------------------------------------

alter table next_step_decisions enable row level security;
alter table next_step_routing   enable row level security;

create policy own_decision on next_step_decisions
  for select using (user_id = auth.uid() or is_staff());
create policy make_decision on next_step_decisions
  for insert with check (user_id = auth.uid());
create policy staff_update_decision on next_step_decisions
  for update using (is_staff());
create policy routing_read on next_step_routing
  for select using (is_staff());

-- Kendall, seeded by email like the ministry leaders — links
-- automatically when he first signs in.
-- (leader row lives in db/seed/leaders.sql — not committed)
