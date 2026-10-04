-- Svenska kyrkans kyrkor från OpenStreetMap (import.osm_kyrkor) som komplement till RAÄ:s kyrkor (KY).
-- Läggs in som kalla KO, typ Kyrka. Dubbletter mot RAÄ sorteras bort:
--   1) en RAÄ-kyrka finns inom 75 m, eller
--   2) en RAÄ-kyrka med liknande namn finns inom 300 m.
-- Dubbletter inom OSM (t.ex. både punkt och byggnad för samma kyrka) slås ihop: inom 60 m och liknande namn.
\set ON_ERROR_STOP on
\pset pager off
create extension if not exists pg_trgm with schema extensions;
set search_path = public, extensions;
set statement_timeout = '30min';
begin;

create temp table o as
select osm_id, trim(namn) as namn, regel, ST_SetSRID(ST_MakePoint(lon, lat), 4326) as geom
from import.osm_kyrkor;

select regel, count(*) as antal from o group by 1 order by 1;

delete from o where regel <> 'explicit';
create index on o using gist (geom);
analyze o;

-- Dubbletter inom OSM: behåll byggnaden (way/relation) framför punkten (node)
delete from o a using o b
where a.osm_id <> b.osm_id
  and a.geom && ST_Expand(b.geom, 0.002)                    -- snabb grovsållning med index
  and ST_DWithin(a.geom::geography, b.geom::geography, 60)
  and similarity(lower(a.namn), lower(b.namn)) > 0.4
  and (case when b.osm_id like 'node/%' then 1 else 0 end, b.osm_id) < (case when a.osm_id like 'node/%' then 1 else 0 end, a.osm_id);

create temp table dubblett as
select o.osm_id,
       (select k.namn from public.objekt k where k.kalla = 'KY' and k.geom && ST_Expand(o.geom, 0.003)
          and ST_DWithin(k.geom::geography, o.geom::geography, 75) limit 1) as nara,
       (select k.namn from public.objekt k where k.kalla = 'KY' and k.geom && ST_Expand(o.geom, 0.01)
          and ST_DWithin(k.geom::geography, o.geom::geography, 300)
          and similarity(lower(k.namn), lower(o.namn)) > 0.4 limit 1) as samma_namn
from o;

select count(*) filter (where nara is not null)                       as dubblett_inom_75m,
       count(*) filter (where nara is null and samma_namn is not null) as dubblett_namn_inom_300m,
       count(*) filter (where nara is null and samma_namn is null)     as nya
from dubblett;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'KO', 'kultur', 'Kyrka', o.osm_id, o.namn, o.geom,
       jsonb_build_object('kalla', 'OpenStreetMap', 'url', 'https://www.openstreetmap.org/' || o.osm_id), now()
from o join dubblett d using (osm_id)
where d.nara is null and d.samma_namn is null
on conflict (kalla, ext_id) do update set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

delete from public.objekt k
where k.kalla = 'KO'
  and not exists (select 1 from o join dubblett d using (osm_id) where d.nara is null and d.samma_namn is null and o.osm_id = k.ext_id);

drop table import.osm_kyrkor;
commit;

select count(*) as kyrkor_fran_osm from public.objekt where kalla = 'KO';
select namn from public.objekt where kalla = 'KO' order by random() limit 10;
select kalla, namn from public.objekt where kalla in ('KY', 'KO') and namn ilike 'Sanda kyrka%';
