-- =============================================================
--  THE JOURNEY · migration 012
--  Roles inside each ministry.
--
--  "Behind the Scenes" is a ladder and a paint bucket, and it is
--  also a spreadsheet. Someone who would love one may run from
--  the other. The ministry tells you WHO follows up; the role
--  tells them WHAT to talk about.
-- =============================================================

create table ministry_roles (
  id          uuid primary key default gen_random_uuid(),
  ministry_id uuid not null references ministries on delete cascade,
  name        text not null,
  blurb       text,                       -- plain words, no church jargon
  suits_gifts spiritual_gift[] not null default '{}',
  effort      text check (effort in ('hands_on','people','desk','creative')),
  is_active   boolean not null default true,
  sort_order  int not null default 100,
  unique (ministry_id, name)
);
create index on ministry_roles (ministry_id) where is_active;

insert into ministry_roles (ministry_id, name, blurb, suits_gifts, effort, sort_order)
select resolve_ministry(r.min), r.name, r.blurb, r.gifts::spiritual_gift[], r.effort, r.ord
from (values
-- Next Steps
('Next Steps','Welcoming first-time guests','Being the first friendly face someone meets.','{evangelism,hospitality,exhortation}','people',1),
('Next Steps','Follow-up and connection','Reaching out after a visit so nobody slips away.','{shepherding,exhortation,mercy_showing}','people',2),
('Next Steps','Missions and outreach','Taking the gospel beyond our walls.','{evangelism,apostleship,faith}','people',3),
('Next Steps','Community service','Serving Miami through practical need.','{mercy_showing,serving,giving}','hands_on',4),
-- Hospitality
('Hospitality','Greeting and ushering','Welcoming people in and helping them find their place.','{hospitality,serving,exhortation}','people',1),
('Hospitality','Food and refreshments','Feeding people well, because it matters.','{hospitality,serving,giving}','hands_on',2),
('Hospitality','Event setup','Getting rooms ready before anyone arrives.','{serving,craftsmanship}','hands_on',3),
-- Worship
('Worship','Vocals','Singing on the worship team.','{creative_communication,faith}','creative',1),
('Worship','Instruments','Playing on the worship team.','{creative_communication,craftsmanship}','creative',2),
('Worship','Worship planning','Choosing songs and shaping the service.','{creative_communication,leadership,discernment}','desk',3),
-- Student Ministry
('Student Ministry','Students','Walking with teenagers.','{teaching,shepherding,exhortation}','people',1),
('Student Ministry','Young adults','Walking with young adults.','{teaching,shepherding,exhortation}','people',2),
('Student Ministry','Mentoring','One-on-one with a young person over time.','{shepherding,exhortation,wisdom}','people',3),
-- Children's
('Children''s Ministry / Seekers','Teaching a class','Leading a group of children.','{teaching,shepherding,mercy_showing}','people',1),
('Children''s Ministry / Seekers','Check-in and child safety','Keeping children safe and parents confident.','{administration,serving,discernment}','desk',2),
('Children''s Ministry / Seekers','Crafts and activities','Making Sabbath something children look forward to.','{creative_communication,craftsmanship,serving}','creative',3),
-- Life Groups
('Life Groups','Hosting a group','Opening your home. No Bible expertise needed.','{hospitality,shepherding}','people',1),
('Life Groups','Co-leading a group','Sharing the load of leading with someone else.','{shepherding,teaching,leadership}','people',2),
('Life Groups','Gatherings and events','Planning the things that bring us together.','{administration,hospitality,serving}','hands_on',3),
('Life Groups','Life-on-life discipleship','Walking closely with one person as they grow.','{shepherding,teaching,exhortation}','people',4),
-- Production
('Production','Sound','Running audio for the service.','{craftsmanship,serving,knowledge}','hands_on',1),
('Production','Video and livestream','Cameras and the online service.','{craftsmanship,creative_communication,knowledge}','hands_on',2),
('Production','Lighting','Lighting the room and the stage.','{craftsmanship,serving}','hands_on',3),
('Production','Slides','Running lyrics and graphics live.','{serving,knowledge,administration}','desk',4),
-- Creative and Social
('Creative and Social','Graphic design','Designing what ARISE looks like.','{creative_communication,craftsmanship}','creative',1),
('Creative and Social','Photo and video content','Capturing and telling our story.','{creative_communication,craftsmanship}','creative',2),
('Creative and Social','Social media','Posting, replying, and building community online.','{creative_communication,evangelism,knowledge}','creative',3),
-- Behind the Scenes  ← the split that prompted all this
('Behind the Scenes','Facilities and maintenance','Practical, hands-on work — repairs, upkeep, setup. Comfortable shoes.','{craftsmanship,serving,giving}','hands_on',1),
('Behind the Scenes','Office and administration','Organizing, records, spreadsheets, coordination. Desk work.','{administration,knowledge,serving}','desk',2),
('Behind the Scenes','Resources and supplies','Keeping the church stocked and running.','{administration,serving,giving}','desk',3)
) as r(min, name, blurb, gifts, effort, ord)
where resolve_ministry(r.min) is not null
on conflict (ministry_id, name) do nothing;

-- ---------- carry the role through the handoff ---------------

alter table ministry_interests
  add column if not exists role_id uuid references ministry_roles;

create index on ministry_interests (role_id);

-- Role-level suggestions beat ministry-level ones: someone whose
-- gift is Craftsmanship should see Facilities, not "Behind the
-- Scenes" and a guess.
create or replace function roles_for(p_user uuid, p_limit int default 5)
returns table (role_id uuid, ministry text, role_name text, blurb text, matches int)
language sql stable as $$
  with g as (
    select array[gift_1,gift_2,gift_3] as gifts
    from spiritual_gifts_results where user_id = p_user
  )
  select r.id, m.name, r.name, r.blurb,
         coalesce(cardinality(array(
           select unnest(r.suits_gifts) intersect select unnest(g.gifts))), 0)
  from ministry_roles r
  join ministries m on m.id = r.ministry_id
  left join g on true
  where r.is_active and m.is_active and not m.is_discernment
  order by 5 desc, m.sort_order, r.sort_order
  limit p_limit;
$$;

-- What the leader actually reads in the notification.
create or replace view v_open_handoffs_detailed as
select mi.id,
       p.full_name      as person,
       p.email          as person_email,
       p.phone          as person_phone,
       m.name           as ministry,
       r.name           as role,
       r.effort,
       mi.status,
       mi.is_discernment,
       extract(day from now() - mi.expressed_at)::int as days_open,
       mi.escalated_at is not null as escalated,
       coalesce(
         (select string_agg(gl.label, ', ')
          from spiritual_gifts_results s
          join gift_labels gl on gl.gift in (s.gift_1, s.gift_2, s.gift_3)
          where s.user_id = p.id), 'survey not recorded') as their_gifts
from ministry_interests mi
join profiles   p on p.id = mi.user_id
join ministries m on m.id = mi.ministry_id
left join ministry_roles r on r.id = mi.role_id
where mi.status not in ('serving','declined')
order by mi.expressed_at;

alter table ministry_roles enable row level security;
create policy roles_read on ministry_roles for select using (is_active or is_staff());
create policy roles_write on ministry_roles for all using (is_staff());
