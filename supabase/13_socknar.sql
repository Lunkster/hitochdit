-- Socknar och städer (Lantmäteriet, Sockenstad) i tabellen indelning (typ = 'socken') + socken på varje besök.
-- Kör i SQL Editor INNAN tools/ladda_socknar.sh. Går att köra om.
-- Socknar kryssas automatiskt (punkt-i-polygon) men räknas bara i egen statistik, inte i topplistor.

alter table public.indelning add column if not exists undertyp text;   -- socken | stad (för typ = socken)
alter table public.besok add column if not exists sockenkod text;
create index if not exists besok_socken on public.besok (user_id, sockenkod);

-- Kommun, län och socken på besöket. Punkter strax utanför (t.ex. fyrar till havs) får närmaste inom 25 km.
create or replace function public.besok_satt_indelning() returns trigger
language plpgsql set search_path = public, extensions as $$
declare pt extensions.geometry := public.besok_punkt(new);
begin
  if pt is not null then
    select i.kod, i.lanskod into new.kommunkod, new.lanskod
    from public.indelning i
    where i.typ = 'kommun' and i.geom && ST_Expand(pt, 0.5) and ST_DWithin(i.geom::geography, pt::geography, 25000)
    order by ST_Distance(i.geom::geography, pt::geography) limit 1;
    select i.kod into new.sockenkod
    from public.indelning i
    where i.typ = 'socken' and i.geom && ST_Expand(pt, 0.5) and ST_DWithin(i.geom::geography, pt::geography, 25000)
    order by ST_Distance(i.geom::geography, pt::geography) limit 1;
  end if;
  return new;
end $$;
