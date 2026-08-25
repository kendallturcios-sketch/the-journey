-- Copy to leaders.sql and fill in real details. leaders.sql is gitignored.
insert into pending_leaders (ministry, full_name, email, phone, is_primary) values
('Next Steps','First Last','name@example.org','+13055550100',true),
('Hospitality','First Last','name@example.org','+13055550101',true),
('Hospitality','First Last','name@example.org','+13055550102',false),
('Worship','First Last','name@example.org','+13055550103',true),
('Student Ministry','First Last','name@example.org','+13055550104',true),
('Life Groups','First Last','name@example.org','+13055550105',true),
('Production','First Last','name@example.org','+13055550106',true),
('Children''s Ministry / Seekers','First Last','name@example.org','+13055550107',true),
('Behind the Scenes','First Last','name@example.org','+13055550108',true),
('Creative and Social','TBD','tbd@example.org',null,true)
on conflict do nothing;

update next_step_routing set pastor_email = 'pastor@example.org';
