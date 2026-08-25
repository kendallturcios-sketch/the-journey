-- =============================================================
--  THE JOURNEY · migration 015
--  Gift routing, as decided by Arise.
--
--  These decide what gets HIGHLIGHTED first. Every ministry and
--  every role stays selectable by anyone, whatever the survey
--  returned. A gift opens a door; it never closes one.
-- =============================================================

update ministries     set suits_gifts = '{}';
update ministry_roles set suits_gifts = '{}';

select map_gift('evangelism',     'Next Steps');
select map_gift('evangelism',     'Student Ministry');
select map_gift('evangelism',     'Life Groups');

select map_gift('prophecy',       'Next Steps');
select map_gift('prophecy',       'Hospitality');
select map_gift('prophecy',       'Children''s Ministry / Seekers');

select map_gift('teaching',       'Life Groups');
select map_gift('teaching',       'Next Steps');
select map_gift('teaching',       'Student Ministry');

select map_gift('exhortation',    'Life Groups');
select map_gift('exhortation',    'Next Steps');
select map_gift('exhortation',    'Creative and Social');

select map_gift('shepherding',    'Hospitality');
select map_gift('shepherding',    'Life Groups');
select map_gift('shepherding',    'Student Ministry');

select map_gift('serving',        'Next Steps');
select map_gift('serving',        'Hospitality');
select map_gift('serving',        'Behind the Scenes');

select map_gift('mercy_showing',  'Children''s Ministry / Seekers');
select map_gift('mercy_showing',  'Hospitality');
select map_gift('mercy_showing',  'Next Steps');

select map_gift('giving',         'Next Steps');
select map_gift('giving',         'Hospitality');
select map_gift('giving',         'Children''s Ministry / Seekers');

select map_gift('administration', 'Production');
select map_gift('administration', 'Creative and Social');
select map_gift('administration', 'Behind the Scenes');

-- ---------- coverage check -----------------------------------
-- Worship currently has no gift pointing to it. It still appears
-- in the picker and anyone can choose it — it just never gets
-- highlighted. Run this after any change to the mapping.

create or replace view v_gift_coverage as
select m.name as ministry,
       coalesce(cardinality(m.suits_gifts), 0) as gifts_pointing_here,
       coalesce(
         (select string_agg(gl.label, ', ' order by gl.sort_order)
          from gift_labels gl where gl.gift = any(m.suits_gifts)),
         'none') as which_gifts
from ministries m
where m.is_active and not m.is_discernment
order by 2 desc, m.sort_order;

select * from v_gift_coverage;
