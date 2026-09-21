-- =============================================================
--  THE JOURNEY · migration 018
--  Church Center form ids for Levels 2-4, confirmed against the
--  live form titles ("The Journey - Level Two" etc.) on 2026-09-21.
--  Level 1 (480411) was added in 009.
-- =============================================================

insert into legacy_forms (level_order, form_id, form_url) values
  (2,'494110','https://arisemiami.churchcenter.com/people/forms/494110'),
  (3,'494099','https://arisemiami.churchcenter.com/people/forms/494099'),
  (4,'494115','https://arisemiami.churchcenter.com/people/forms/494115')
on conflict (level_order) do update
  set form_id = excluded.form_id, form_url = excluded.form_url;
