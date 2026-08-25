-- =============================================================
--  THE JOURNEY · migration 006
--  Sessions start at 9:00 AM.
-- =============================================================

create or replace function generate_journey_calendar(
  p_from      date,
  p_months    int,
  p_start_time time default '09:00',
  p_location  text default 'Arise Miami SDA Church'
) returns int language plpgsql as $$
declare
  m date; n int; d date; made int := 0; v_level uuid;
begin
  for i in 0 .. p_months - 1 loop
    m := (date_trunc('month', p_from) + (i || ' months')::interval)::date;
    for n in 1 .. 4 loop
      -- nth Saturday of month m
      d := m + ((6 - extract(dow from m)::int + 7) % 7) + ((n - 1) * 7);
      if extract(month from d) = extract(month from m) then
        select id into v_level from levels where sabbath_of_month = n;
        insert into sessions (level_id, meets_on, starts_at, location)
        values (v_level, d,
                (d + p_start_time) at time zone 'America/New_York',
                p_location)
        on conflict (level_id, meets_on) do nothing;
        made := made + 1;
      end if;
    end loop;
  end loop;
  return made;
end;
$$;

-- Shift anything already generated at the old default.
update sessions
set starts_at = (meets_on + time '09:00') at time zone 'America/New_York'
where starts_at <> (meets_on + time '09:00') at time zone 'America/New_York';

-- Build twelve months from next month:
--   select generate_journey_calendar(
--     (date_trunc('month', now()) + interval '1 month')::date, 12);
