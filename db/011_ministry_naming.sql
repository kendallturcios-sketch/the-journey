-- =============================================================
--  THE JOURNEY · migration 011
--  Media/Tech means the sound booth to most people, so it now
--  routes to Production. Design and social media is its own
--  ministry, plainly named.
-- =============================================================

update ministries
set name  = 'Creative and Social',
    blurb = 'Design and social media — how ARISE looks and sounds online.'
where name = 'Creative';

update ministry_aliases
set ministry_id = (select id from ministries where name = 'Production'),
    note        = 'people saying Media/Tech mean sound, video and lighting'
where lower(alias) in ('media/tech','tech/media','media','media/tech excellence');

insert into ministry_aliases (alias, ministry_id, note)
select a.alias, m.id, a.note
from (values
  ('Tech/Media Team',      'Production',          'sound, video, lighting'),
  ('Media/Tech Excellence','Production',          'sound, video, lighting'),
  ('Creative',             'Creative and Social', 'renamed'),
  ('Social Media',         'Creative and Social', 'same team'),
  ('Design',               'Creative and Social', 'same team'),
  ('Graphics',             'Creative and Social', 'same team')
) as a(alias, target, note)
join ministries m on m.name = a.target
on conflict (alias) do update
  set ministry_id = excluded.ministry_id, note = excluded.note;

-- Anyone who already picked Creative before the split gets moved
-- to Production only if they said Media/Tech. Nobody is stranded.
update ministry_interests mi
set ministry_id = (select id from ministries where name = 'Production')
where mi.ministry_id = (select id from ministries where name = 'Creative and Social')
  and mi.status = 'expressed'
  and exists (select 1 from ministry_aliases a
              where a.ministry_id = mi.ministry_id
                and lower(a.alias) = 'media/tech');

-- Sanity check — run this and read the output.
select m.name,
       m.sort_order,
       coalesce(string_agg(a.alias, ', ' order by a.alias), '—') as also_known_as,
       (select count(*) from ministry_leaders ml where ml.ministry_id = m.id)
         + (select count(*) from pending_leaders pl
            where resolve_ministry(pl.ministry) = m.id and pl.linked_at is null)
         as leaders
from ministries m
left join ministry_aliases a on a.ministry_id = m.id
where m.is_active
group by m.id, m.name, m.sort_order
order by m.sort_order;
