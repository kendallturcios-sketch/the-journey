-- =============================================================
--  THE JOURNEY · migration 014
--  The nine gifts, and only the nine.
--
--  Names, definitions and passages kept from the Level 3 guide.
--  The other ten are gone — no facilitator can read out a gift
--  the survey cannot score.
--
--  Gift-to-ministry mapping is now EMPTY on purpose. Arise is
--  supplying it; my guesses have been cleared out so they can't
--  quietly survive underneath the real thing.
-- =============================================================

alter table gift_labels add column if not exists bsb_text text;

delete from gift_labels
where gift in ('apostleship','craftsmanship','creative_communication',
               'discernment','faith','hospitality','intercession',
               'knowledge','leadership','wisdom');

insert into gift_labels (gift,label,definition,scripture,bsb_text,sort_order) values
('evangelism','Evangelism','A special ability and enthusiasm for communicating the good news of salvation in Christ to those who are not yet believers.','Acts 8:4-8','4 Those who had been scattered preached the word wherever they went. 5 Philip went down to a city in Samaria and proclaimed the Christ to them. 6 The crowds gave their undivided attention to Philip’s message and to the signs they saw him perform. 7 With loud shrieks, unclean spirits came out of many who were possessed, and many of the paralyzed and lame were healed. 8 So there was great joy in that city.',1),
('prophecy','Prophecy','The special ability to receive and communicate a timely message from God to an individual or group, usually in the form of confrontation of sinful behavior.','Acts 27:21-26','21 After the men had gone a long time without food, Paul stood up among them and said, “Men, you should have followed my advice not to sail from Crete. Then you would have averted this disaster and loss. 22 But now I urge you to keep up your courage, because you will not experience any loss of life, but only of the ship. 23 For just last night an angel of God, whose I am and whom I serve, stood beside me 24 and said, ‘Do not be afraid, Paul; you must stand before Caesar. And look, God has granted you the lives of all who sail with you.’ 25 So take courage, men, for I believe God that it will happen just as He told me. 26 However, we must run aground on some island.”',2),
('teaching','Teaching / Preaching','The ability to understand spiritual truths and to explain them clearly to others.','Acts 20:20','I did not shrink back from declaring anything that was helpful to you as I taught you publicly and from house to house,',3),
('exhortation','Exhortation / Encouragement','The gift of being able to effectively offer appropriate words of comfort, consolation or encouragement to those who are discouraged, confused or wavering in their faith, motivating them to grow toward personal wholeness or spiritual maturity.','Acts 11:22-24','22 When news of this reached the ears of the church in Jerusalem, they sent Barnabas to Antioch. 23 When he arrived and saw the grace of God, he rejoiced and encouraged them all to abide in the Lord with all their hearts. 24 Barnabas was a good man, full of the Holy Spirit and faith, and a great number of people were brought to the Lord.',4),
('shepherding','Shepherding','A God-given ability to care for the spiritual needs of a group of believers and to lead and nurture them to grow in their faith.','1 Peter 5:1-4','1 As a fellow elder, a witness of Christ’s sufferings, and a partaker of the glory to be revealed, I appeal to the elders among you: 2 Be shepherds of God’s flock that is among you, watching over them not out of compulsion, but because it is God’s will; not out of greed, but out of eagerness; 3 not lording it over those entrusted to you, but being examples to the flock. 4 And when the Chief Shepherd appears, you will receive the crown of glory that will never fade away.',5),
('serving','Serving / Helps','A gift for bringing spiritual value to the accomplishment of tasks, working alongside others and freeing them to use their own gifts.','Acts 9:36','In Joppa there was a disciple named Tabitha (which is translated as Dorcas), who was always occupied with works of kindness and charity.',6),
('mercy_showing','Mercy-Showing','The gift from God to feel empathy and compassion for people in pain, from whatever the cause, accompanied by a strong desire to minister appropriately to those people and alleviate their suffering.','Acts 16:33','At that hour of the night, the jailer took them and washed their wounds. And without delay, he and all his household were baptized.',7),
('giving','Giving / Generosity','A God-given love for sharing whatever resources one has, whether much or little, for the benefit of the Body of Christ.','Luke 21:1-4','1 Then Jesus looked up and saw the rich putting their gifts into the treasury, 2 and He saw a poor widow put in two small copper coins. 3 “Truly I tell you,” He said, “this poor widow has put in more than all the others. 4 For they all contributed out of their surplus, but she out of her poverty has put in all she had to live on.”',8),
('administration','Administration','The special ability to understand immediate and long-range goals and to organize people, information and materials to accomplish those goals.','Acts 6:2-7','2 So the Twelve summoned all the disciples and said, “It is unacceptable for us to neglect the word of God in order to wait on tables. 3 Therefore, brothers, select from among you seven men confirmed to be full of the Spirit and wisdom. We will appoint this responsibility to them 4 and will devote ourselves to prayer and to the ministry of the word.” 5 This proposal pleased the whole group. They chose Stephen, a man full of faith and of the Holy Spirit, as well as Philip, Prochorus, Nicanor, Timon, Parmenas, and Nicolas from Antioch, a convert to Judaism. 6 They presented these seven to the apostles, who prayed and laid their hands on them. 7 So the word of God continued to spread. The number of disciples in Jerusalem grew rapidly, and a great number of priests became obedient to the faith.',9)
on conflict (gift) do update set
  label      = excluded.label,
  definition = excluded.definition,
  scripture  = excluded.scripture,
  bsb_text   = excluded.bsb_text,
  sort_order = excluded.sort_order,
  is_active  = true,
  retired_note = null;

-- Note: the Level 3 guide cited Luke 12:1-4 for Giving but quoted
-- the widow's offering, which is Luke 21:1-4. Corrected here.

-- ---------- clear my invented mappings -----------------------
-- A gift suggests; it never restricts. Someone with Serving can
-- serve anywhere, so every ministry and role stays selectable no
-- matter what the survey said.

update ministries      set suits_gifts = '{}';
update ministry_roles  set suits_gifts = '{}';

-- Suggestions are advisory only. With no mapping loaded this
-- returns everything in normal order, which is the correct
-- behaviour: show all the doors, highlight none.
create or replace function roles_for(p_user uuid, p_limit int default 5)
returns table (role_id uuid, ministry text, role_name text, blurb text,
               matches int, suggested boolean)
language sql stable as $$
  with g as (
    select array[gift_1,gift_2,gift_3] as gifts
    from spiritual_gifts_results where user_id = p_user
  )
  select r.id, m.name, r.name, r.blurb,
         coalesce(cardinality(array(
           select unnest(r.suits_gifts) intersect select unnest(g.gifts))), 0),
         coalesce(cardinality(array(
           select unnest(r.suits_gifts) intersect select unnest(g.gifts))), 0) > 0
  from ministry_roles r
  join ministries m on m.id = r.ministry_id
  left join g on true
  where r.is_active and m.is_active and not m.is_discernment
  order by 5 desc, m.sort_order, r.sort_order
  limit p_limit;
$$;

-- Ready for the mapping Arise supplies. One row per pairing:
--   select map_gift('serving', 'Hospitality');
create or replace function map_gift(p_gift text, p_target text)
returns void language plpgsql as $$
declare v uuid;
begin
  v := resolve_ministry(p_target);
  if v is not null then
    update ministries set suits_gifts = array(
      select distinct unnest(suits_gifts || p_gift::spiritual_gift))
    where id = v;
    return;
  end if;
  update ministry_roles set suits_gifts = array(
    select distinct unnest(suits_gifts || p_gift::spiritual_gift))
  where lower(name) = lower(p_target);
end;
$$;

select label, scripture, left(bsb_text, 60) || '...' as passage
from gift_labels where is_active order by sort_order;
