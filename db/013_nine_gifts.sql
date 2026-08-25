-- =============================================================
--  THE JOURNEY · migration 013
--  Back to the nine gifts the survey actually measures.
--
--  A facilitator must never read out a gift the assessment
--  cannot score. Migration 010 expanded this to 19 from the
--  Level 3 guide; that was my error and this reverses it.
--
--  The ten are deactivated, not deleted — Postgres cannot drop
--  enum values, and keeping them means any historical record
--  still reads correctly.
-- =============================================================

alter table gift_labels
  add column if not exists is_active boolean not null default true,
  add column if not exists retired_note text;

update gift_labels
set is_active = false,
    retired_note = 'Not measured by the ChurchGrowth survey — retired 2026'
where gift in ('apostleship','craftsmanship','creative_communication',
               'discernment','faith','hospitality','intercession',
               'knowledge','leadership','wisdom');

-- Renumber the nine that remain.
update gift_labels set sort_order = v.ord
from (values
  ('evangelism',1),('prophecy',2),('teaching',3),('exhortation',4),
  ('shepherding',5),('serving',6),('mercy_showing',7),('giving',8),
  ('administration',9)
) as v(g, ord)
where gift_labels.gift = v.g::spiritual_gift;

-- Nothing new can be recorded against a retired gift.
create or replace function gifts_must_be_active()
returns trigger language plpgsql as $$
declare bad text;
begin
  select string_agg(gl.label, ', ') into bad
  from gift_labels gl
  where gl.gift in (new.gift_1, new.gift_2, new.gift_3) and not gl.is_active;
  if bad is not null then
    raise exception 'Not measured by the survey: %', bad;
  end if;
  return new;
end;
$$;

create trigger trg_gifts_active
  before insert or update on spiritual_gifts_results
  for each row execute function gifts_must_be_active();

-- ---------- remap everything onto the nine -------------------

update ministries set suits_gifts = v.g::spiritual_gift[]
from (values
  ('Next Steps',                   '{evangelism,exhortation,shepherding}'),
  ('Hospitality',                  '{serving,mercy_showing,giving}'),
  ('Worship',                      '{exhortation,serving,prophecy}'),
  ('Student Ministry',             '{teaching,shepherding,exhortation}'),
  ('Children''s Ministry / Seekers','{teaching,mercy_showing,shepherding,serving}'),
  ('Life Groups',                  '{shepherding,exhortation,teaching}'),
  ('Production',                   '{serving,administration}'),
  ('Creative and Social',          '{evangelism,exhortation,administration}'),
  ('Behind the Scenes',            '{administration,serving,giving}')
) as v(n, g)
where ministries.name = v.n;

update ministry_roles set suits_gifts = v.g::spiritual_gift[]
from (values
  ('Welcoming first-time guests','{evangelism,exhortation}'),
  ('Follow-up and connection','{shepherding,exhortation,mercy_showing}'),
  ('Missions and outreach','{evangelism,giving}'),
  ('Community service','{mercy_showing,serving,giving}'),
  ('Greeting and ushering','{serving,exhortation}'),
  ('Food and refreshments','{serving,giving}'),
  ('Event setup','{serving}'),
  ('Vocals','{exhortation,serving}'),
  ('Instruments','{serving}'),
  ('Worship planning','{administration,prophecy}'),
  ('Students','{teaching,shepherding}'),
  ('Young adults','{teaching,shepherding}'),
  ('Mentoring','{shepherding,exhortation}'),
  ('Teaching a class','{teaching,mercy_showing}'),
  ('Check-in and child safety','{administration,serving}'),
  ('Crafts and activities','{serving,mercy_showing}'),
  ('Hosting a group','{serving,shepherding}'),
  ('Co-leading a group','{shepherding,teaching}'),
  ('Gatherings and events','{administration,serving}'),
  ('Life-on-life discipleship','{shepherding,exhortation,teaching}'),
  ('Sound','{serving}'),
  ('Video and livestream','{serving}'),
  ('Lighting','{serving}'),
  ('Slides','{serving,administration}'),
  ('Graphic design','{serving}'),
  ('Photo and video content','{serving,evangelism}'),
  ('Social media','{evangelism,exhortation}'),
  ('Facilities and maintenance','{serving,giving}'),
  ('Office and administration','{administration}'),
  ('Resources and supplies','{administration,giving}')
) as v(n, g)
where ministry_roles.name = v.n;

-- ---------- what the app reads -------------------------------

create or replace view v_gifts as
select gift, label, definition, scripture, sort_order
from gift_labels
where is_active
order by sort_order;

-- Honest check: with only nine gifts, Serving carries a lot of
-- weight. Run this to see how evenly the roles are spread.
select gl.label,
       count(r.id) as roles_matched
from gift_labels gl
left join ministry_roles r on gl.gift = any(r.suits_gifts)
where gl.is_active
group by gl.label, gl.sort_order
order by gl.sort_order;
