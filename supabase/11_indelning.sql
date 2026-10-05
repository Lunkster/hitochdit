-- Kommuner och län (Lantmäteriet) + automatisk kommun/län på varje besök.
-- Kör i SQL Editor INNAN tools/ladda_indelning.sh. Går att köra om.

create table if not exists public.indelning (
  typ       text not null,                 -- kommun | lan
  kod       text not null,                 -- kommunkod (0114) resp. länskod (01)
  namn      text not null,                 -- Upplands Väsby kommun / Stockholms län
  kortnamn  text,                          -- Upplands Väsby / Stockholm
  lanskod   text,
  lansbokstav text,
  geom      extensions.geometry(MultiPolygon, 4326) not null,
  uppdaterad timestamptz not null default now(),
  primary key (typ, kod)
);
create index if not exists indelning_geom_idx on public.indelning using gist (geom);
alter table public.indelning enable row level security;
drop policy if exists "indelning: alla kan läsa" on public.indelning;
create policy "indelning: alla kan läsa" on public.indelning for select to anon, authenticated using (true);

-- Kommun och län på besöken
alter table public.besok add column if not exists kommunkod text;
alter table public.besok add column if not exists lanskod text;
create index if not exists besok_kommun on public.besok (user_id, kommunkod);

-- Vilken kommun/län ligger en punkt i? Punkter strax utanför (t.ex. fyrar till havs) får närmaste kommun inom 25 km.
create or replace function public.indelning_vid(lat double precision, lon double precision)
returns table (typ text, kod text, namn text, kortnamn text, lanskod text)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt)
  select distinct on (i.typ) i.typ, i.kod, i.namn, i.kortnamn, i.lanskod
  from public.indelning i, p
  where i.geom && ST_Expand(p.pt, 0.5)
    and ST_DWithin(i.geom::geography, p.pt::geography, 25000)
  order by i.typ, ST_Distance(i.geom::geography, p.pt::geography);
$$;
grant execute on function public.indelning_vid(double precision, double precision) to anon, authenticated;

-- Punkt för ett besök: loggad position, annars en punkt på det besökta objektet
create or replace function public.besok_punkt(b public.besok) returns extensions.geometry
language sql stable set search_path = public, extensions as $$
  select coalesce(
    case when b.lat is not null and b.lon is not null then ST_SetSRID(ST_MakePoint(b.lon, b.lat), 4326) end,
    (select ST_PointOnSurface(o.geom) from public.objekt o where o.kalla = b.scheme and o.ext_id = b.objekt_id limit 1),
    (select ST_PointOnSurface(o.geom) from public.objekt o where o.kalla in ('NR', 'NP', 'KR') and o.ext_id = b.nvrid limit 1));
$$;

create or replace function public.besok_satt_indelning() returns trigger
language plpgsql set search_path = public, extensions as $$
declare pt extensions.geometry := public.besok_punkt(new);
begin
  if pt is not null then
    select i.kod, i.lanskod into new.kommunkod, new.lanskod
    from public.indelning i
    where i.typ = 'kommun' and i.geom && ST_Expand(pt, 0.5) and ST_DWithin(i.geom::geography, pt::geography, 25000)
    order by ST_Distance(i.geom::geography, pt::geography) limit 1;
  end if;
  return new;
end $$;

drop trigger if exists besok_indelning on public.besok;
create trigger besok_indelning before insert or update of lat, lon, objekt_id, scheme on public.besok
  for each row execute function public.besok_satt_indelning();
