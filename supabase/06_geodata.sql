-- Egen geodatabas i Supabase (PostGIS) för matchning av position mot objekt.
-- Visning i kartan sker fortfarande från källornas WMS; här görs bara frågorna
-- "vilka objekt står jag i/nära?" och "ge mig ytan för mina besökta objekt".
-- Kör i SQL Editor. Går att köra om.

create extension if not exists postgis with schema extensions;

-- Schema för rådata som laddas med ogr2ogr. Exponeras inte i API:t.
create schema if not exists import;

-- ============ Alla objekt från alla källor i en tabell ============
create table if not exists public.objekt (
  id          bigint generated always as identity primary key,
  kalla       text not null,            -- kortkod: VA = världsarv, BM = byggnadsminne, FL = fornlämning, KR = kulturreservat …
  kategori    text not null,            -- natur | kultur
  typ         text not null,            -- visningsnamn: Världsarv, Byggnadsminne, Fornlämning …
  ext_id      text not null,            -- källans id (stabilt mellan uppdateringar)
  namn        text not null,
  geom        extensions.geometry(Geometry, 4326) not null,
  egenskaper  jsonb,                    -- övrigt från källan som kan vara bra att ha
  uppdaterad  timestamptz not null default now(),
  unique (kalla, ext_id)
);
create index if not exists objekt_geom_idx  on public.objekt using gist (geom);
-- (geografi-index borttaget i 10_optimera_utrymme.sql – objekt_vid använder geometri-indexet)
create index if not exists objekt_kalla_idx on public.objekt (kalla);

alter table public.objekt enable row level security;
drop policy if exists "objekt: alla kan läsa" on public.objekt;
create policy "objekt: alla kan läsa" on public.objekt for select to anon, authenticated using (true);

-- ============ Funktioner som appen anropar ============
-- Objekt som punkten ligger i, eller inom radie_m meter från (för punkter/små objekt).
create or replace function public.objekt_vid(lat double precision, lon double precision,
                                             radie_m double precision default 25, kallor text[] default null)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography g)
  select o.kalla, o.kategori, o.typ, o.ext_id, o.namn, round(ST_Distance(o.geom::geography, p.g)::numeric, 1)::double precision
  from public.objekt o, p
  where ST_DWithin(o.geom::geography, p.g, greatest(coalesce(radie_m, 0), 0))
    and (kallor is null or o.kalla = any(kallor))
  order by 6, o.namn
  limit 50;
$$;

-- Förenklade ytor som GeoJSON för en lista nycklar 'KALLA:ext_id' (för besökta objekt).
create or replace function public.objekt_geom(nycklar text[])
returns table (kalla text, ext_id text, typ text, namn text, geojson json)
language sql stable set search_path = public, extensions as $$
  select o.kalla, o.ext_id, o.typ, o.namn,
         ST_AsGeoJSON(ST_SimplifyPreserveTopology(o.geom, 0.00003), 6)::json
  from public.objekt o
  where (o.kalla || ':' || o.ext_id) = any(nycklar)
  limit 500;
$$;

grant execute on function public.objekt_vid(double precision, double precision, double precision, text[]) to anon, authenticated;
grant execute on function public.objekt_geom(text[]) to anon, authenticated;
