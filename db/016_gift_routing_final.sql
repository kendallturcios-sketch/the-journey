-- =============================================================
--  THE JOURNEY · migration 016
--  Gift routing — final. Replaces 015.
--
--  Three ministries per gift, three gifts per ministry.
--  27 pairings, no ministry left without a signal.
--
--  These decide what gets HIGHLIGHTED. Every ministry and role
--  stays selectable by anyone, whatever the survey returned.
-- =============================================================

update ministries     set suits_gifts = '{}';
update ministry_roles set suits_gifts = '{}';

select map_gift('evangelism',     'Life Groups');
select map_gift('evangelism',     'Student Ministry');
select map_gift('evangelism',     'Next Steps');

select map_gift('prophecy',       'Life Groups');
select map_gift('prophecy',       'Creative and Social');
select map_gift('prophecy',       'Production');

select map_gift('teaching',       'Children''s Ministry / Seekers');
select map_gift('teaching',       'Student Ministry');
select map_gift('teaching',       'Creative and Social');

select map_gift('exhortation',    'Next Steps');
select map_gift('exhortation',    'Student Ministry');
select map_gift('exhortation',    'Worship');

select map_gift('shepherding',    'Life Groups');
select map_gift('shepherding',    'Hospitality');
select map_gift('shepherding',    'Next Steps');

select map_gift('serving',        'Worship');
select map_gift('serving',        'Children''s Ministry / Seekers');
select map_gift('serving',        'Production');

select map_gift('mercy_showing',  'Worship');
select map_gift('mercy_showing',  'Hospitality');
select map_gift('mercy_showing',  'Behind the Scenes');

select map_gift('giving',         'Children''s Ministry / Seekers');
select map_gift('giving',         'Hospitality');
select map_gift('giving',         'Behind the Scenes');

select map_gift('administration', 'Behind the Scenes');
select map_gift('administration', 'Creative and Social');
select map_gift('administration', 'Production');

-- Should read 3 across the board.
select * from v_gift_coverage;
