-- =============================================================
--  THE JOURNEY · migration 010
--  Nine ministries. Everything else routes into one of them.
--  Nobody who says yes to serving reaches a dead end.
-- =============================================================

-- ---------- 1. the missing ten gifts -------------------------
-- 004 shipped only the nine team/task gifts from the survey site.
-- Level 3 actually reviews nineteen.

alter type spiritual_gift add value if not exists 'apostleship';
alter type spiritual_gift add value if not exists 'craftsmanship';
alter type spiritual_gift add value if not exists 'creative_communication';
alter type spiritual_gift add value if not exists 'discernment';
alter type spiritual_gift add value if not exists 'faith';
alter type spiritual_gift add value if not exists 'hospitality';
alter type spiritual_gift add value if not exists 'intercession';
alter type spiritual_gift add value if not exists 'knowledge';
alter type spiritual_gift add value if not exists 'leadership';
alter type spiritual_gift add value if not exists 'wisdom';

commit;  -- new enum values must be committed before they can be used

-- Display names live here, so the app never shows a raw enum and
-- Arise can reword a gift without a code change.
create table gift_labels (
  gift       spiritual_gift primary key,
  label      text not null,
  definition text,
  scripture  text,
  sort_order int
);

insert into gift_labels (gift,label,definition,scripture,sort_order) values
('administration','Administration','The special ability to understand immediate and long-range goals and to organize people, information and materials to accomplish them.','Acts 6:2-7',1),
('apostleship','Apostleship','The God-given ability to see the big picture of God''s plan and to begin or organize a ministry, locally or abroad.','Galatians 2:7-8',2),
('craftsmanship','Craftsmanship','The gift of being able to design, construct or repair tangible materials for the benefit of God''s people.','Exodus 31:3-5',3),
('creative_communication','Creative Communication','The special ability to communicate God''s truth through art forms — writing, music, photography and more.','Psalm 150:3-5',4),
('discernment','Discernment','The ability to distinguish between spiritual truth and error in words or behaviour.','Acts 5:1-11',5),
('exhortation','Exhortation / Encouragement','The gift of offering comfort and encouragement to those who are discouraged, confused or wavering.','Acts 11:22-24',6),
('evangelism','Evangelism','A special ability and enthusiasm for communicating the good news of salvation to those who are not yet believers.','Acts 8:4-8',7),
('faith','Faith','An exceptional level of trust in God''s ability to work out His purpose in difficult situations.','Hebrews 11:7',8),
('giving','Giving / Generosity','A God-given love for sharing whatever resources one has, much or little, for the benefit of the Body.','Luke 12:1-4',9),
('serving','Serving / Helps','A gift for bringing spiritual value to tasks, working alongside others and freeing them to use their own gifts.','Acts 9:36',10),
('hospitality','Hospitality','A special joy in providing food and shelter in the name of Christ.','Acts 16:14-15',11),
('intercession','Intercession','A holy joy in spending extended time in prayer for others.','James 5:17-18',12),
('knowledge','Knowledge','The God-given ability to accumulate, remember, analyse and use information effectively.','Colossians 2:1-4',13),
('leadership','Leadership','A unique ability to attract, motivate and work with others to achieve God''s purpose for His Church.','Genesis 37-49',14),
('mercy_showing','Mercy','The gift to feel empathy and compassion for people in pain, with a strong desire to alleviate their suffering.','Acts 16:33',15),
('prophecy','Prophecy','The special ability to receive and communicate a timely message from God to a person or group.','Acts 27:21-26',16),
('shepherding','Shepherd','A God-given ability to care for the spiritual needs of believers and lead them to grow in faith.','1 Peter 5:1-4',17),
('teaching','Teaching / Preaching','The ability to understand spiritual truths and explain them clearly to others.','Acts 20:20',18),
('wisdom','Wisdom','A special gift to discern principles from God''s Word and apply them effectively.','2 Peter 3:15',19)
on conflict (gift) do nothing;

-- The survey returns three ranked gifts, so widen the record.
alter table spiritual_gifts_results
  add column if not exists notes text;

-- ---------- 2. the nine ministries ---------------------------

alter table ministries
  add column if not exists is_discernment boolean not null default false,
  add column if not exists contact_visible boolean not null default false;

insert into ministries (name, blurb, suits_gifts, sort_order) values
('Next Steps',
 'Helping people take their next step and find where they belong.',
 '{evangelism,exhortation,apostleship,faith,shepherding}', 1),
('Hospitality',
 'Making everyone who walks in feel welcomed and cared for.',
 '{hospitality,serving,mercy_showing}', 2),
('Worship',
 'Leading the church into God''s presence through music.',
 '{creative_communication,faith,exhortation}', 3),
('Student Ministry',
 'Walking with students and young adults as they follow Jesus.',
 '{teaching,shepherding,exhortation,leadership}', 4),
('Children''s Ministry / Seekers',
 'Introducing children to Jesus and caring for them well.',
 '{teaching,mercy_showing,shepherding,serving}', 5),
('Life Groups',
 'Life-on-life discipleship in homes, and the events that gather us.',
 '{shepherding,exhortation,teaching,hospitality,leadership}', 6),
('Production',
 'Running the service — sound, video and lighting.',
 '{craftsmanship,serving,knowledge}', 7),
('Creative',
 'Design and social media — how ARISE looks and sounds online.',
 '{creative_communication,craftsmanship,knowledge}', 8),
('Behind the Scenes',
 'Resources, administration and facilities — the work that holds everything up.',
 '{administration,knowledge,giving,leadership,serving}', 9)
on conflict (name) do nothing;

-- NAMES STILL OPEN:
--   'Creative'          was Media/Tech — design & social, NOT equipment
--   'Behind the Scenes' was Resource/Administration
-- Change with a single UPDATE; nothing references these by name.

-- ---------- 3. routing ---------------------------------------
-- Old wording from the printed guides maps onto a real team, so a
-- 2023 handout and the app land the same person in the same place.

create table ministry_aliases (
  alias       text primary key,
  ministry_id uuid not null references ministries on delete cascade,
  note        text
);

insert into ministry_aliases (alias, ministry_id, note)
select a.alias, m.id, a.note
from (values
  ('Events',                     'Life Groups',       'routed per Arise'),
  ('Life-on-Life Discipleship',  'Life Groups',       'same thing, different label'),
  ('Young Adults',               'Student Ministry',  'routed per Arise'),
  ('Missions',                   'Next Steps',        'routed per Arise'),
  ('Community Service',          'Next Steps',        'routed per Arise'),
  ('Serve Miami',                'Next Steps',        'routed per Arise'),
  ('Building/Facilities',        'Behind the Scenes', 'routed per Arise'),
  ('Administration/Coordination','Behind the Scenes', 'routed per Arise'),
  ('Resource/Administration',    'Behind the Scenes', 'renamed'),
  ('Office Admin Help',          'Behind the Scenes', 'routed per Arise'),
  ('Media/Tech',                 'Creative',          'renamed — design & social'),
  ('Tech',                       'Production',        'sound/video/lighting'),
  ('Inspiring Worship',          'Worship',           'renamed'),
  ('Seekers',                    'Children''s Ministry / Seekers', 'same team'),
  ('Students',                   'Student Ministry',  'same team'),
  ('Next Step Team',             'Next Steps',        'renamed'),
  ('Resource/Administration Team','Behind the Scenes','renamed')
) as a(alias, target, note)
join ministries m on m.name = a.target
on conflict (alias) do nothing;

create or replace function resolve_ministry(p_name text)
returns uuid language sql stable as $$
  select coalesce(
    (select id from ministries where lower(name) = lower(p_name)),
    (select ministry_id from ministry_aliases where lower(alias) = lower(p_name))
  );
$$;

-- ---------- 4. leaders ---------------------------------------
-- Seeded by email. When that person signs into the app, the
-- trigger links them automatically — no manual wiring later.

create table pending_leaders (
  id          bigserial primary key,
  ministry    text not null,
  full_name   text not null,
  email       text not null,
  phone       text,
  is_primary  boolean not null default true,
  linked_at   timestamptz,
  unique (ministry, email)
);

-- (leader rows live in db/seed/leaders.sql — not committed)
-- Creative has no leader yet. Its handoffs escalate straight to
-- moderators until one is named.

create or replace function link_pending_leader()
returns trigger language plpgsql security definer as $$
begin
  insert into ministry_leaders (ministry_id, user_id, is_primary)
  select resolve_ministry(pl.ministry), new.id, pl.is_primary
  from pending_leaders pl
  where lower(pl.email) = lower(new.email)
    and resolve_ministry(pl.ministry) is not null
  on conflict do nothing;

  update pending_leaders set linked_at = now()
  where lower(email) = lower(new.email);
  return new;
end;
$$;

create trigger trg_link_leader
  after insert on profiles
  for each row execute function link_pending_leader();

-- ---------- 5. the discernment track -------------------------
-- "I'm not sure yet, but I want to serve" is not a ministry.
-- It is a yes with no address, and it has a short shelf life.

insert into ministries (name, blurb, is_discernment, sort_order)
values ('Not sure yet — but I want to serve',
        'We''ll help you find where you fit.', true, 99)
on conflict (name) do nothing;

insert into ministry_aliases (alias, ministry_id, note)
select 'I''m not sure yet, but I want to serve', id, 'discernment track'
from ministries where is_discernment
on conflict do nothing;

-- Route it to Next Steps, but keep the flag so it gets its own
-- clock and its own close condition.
alter table ministry_interests
  add column if not exists is_discernment boolean not null default false,
  add column if not exists placed_ministry_id uuid references ministries,
  add column if not exists tried_once_on date;

create or replace function flag_discernment()
returns trigger language plpgsql as $$
begin
  if exists (select 1 from ministries
             where id = new.ministry_id and is_discernment) then
    new.is_discernment := true;
  end if;
  return new;
end;
$$;

create trigger trg_flag_discernment
  before insert on ministry_interests
  for each row execute function flag_discernment();

-- Suggest real teams from their own gifts, so "not sure" never
-- shows a blank screen. Falls back to everything if no survey.
create or replace function ministries_for(p_user uuid, p_limit int default 3)
returns table (ministry_id uuid, name text, blurb text, matches int)
language sql stable as $$
  with g as (
    select array[gift_1,gift_2,gift_3] as gifts
    from spiritual_gifts_results where user_id = p_user
  )
  select m.id, m.name, m.blurb,
         coalesce(cardinality(array(
           select unnest(m.suits_gifts) intersect select unnest(g.gifts))), 0)
  from ministries m left join g on true
  where m.is_active and not m.is_discernment
  order by 4 desc, m.sort_order
  limit p_limit;
$$;

-- Tighter clock: 3 days to first contact, 30 days to be placed.
create or replace function stale_discernment()
returns table (interest_id uuid, person text, days_open int, stage text)
language sql stable as $$
  select mi.id, p.full_name,
         extract(day from now() - mi.expressed_at)::int,
         case
           when mi.contacted_at is null then 'never contacted'
           when mi.placed_ministry_id is null then 'contacted, not placed'
         end
  from ministry_interests mi
  join profiles p on p.id = mi.user_id
  where mi.is_discernment
    and mi.status not in ('serving','declined')
    and (
      (mi.contacted_at is null and mi.expressed_at < now() - interval '3 days')
      or (mi.placed_ministry_id is null and mi.expressed_at < now() - interval '30 days')
    )
  order by mi.expressed_at;
$$;

-- Closes only when they land somewhere real.
create or replace function place_person(p_interest uuid, p_ministry uuid)
returns void language plpgsql security definer as $$
begin
  update ministry_interests
  set placed_ministry_id = p_ministry, status = 'serving', closed_at = now()
  where id = p_interest;

  insert into ministry_interests (user_id, ministry_id, status, contacted_at, closed_at)
  select user_id, p_ministry, 'serving', now(), now()
  from ministry_interests where id = p_interest
  on conflict (user_id, ministry_id) do nothing;
end;
$$;

alter table gift_labels        enable row level security;
alter table ministry_aliases   enable row level security;
create policy gift_labels_read on gift_labels for select using (true);
create policy aliases_read     on ministry_aliases for select using (true);
