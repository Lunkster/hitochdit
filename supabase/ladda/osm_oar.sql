-- Lägger in de 300 största öarna från import.osm_oar (byggd av osm_oar_rapport.sql) i public.objekt (kalla = OE).
-- ext_id = OSM-id (t.ex. relation/123). Körs av tools/ladda_osm_oar.sh --ladda.
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table oe as
select ext_id, coalesce(namn, 'Namnlös ö') as namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_SimplifyPreserveTopology(geom, 0.00005)), 3)) as geom,
       jsonb_strip_nulls(jsonb_build_object('rang', rang, 'lista', 300, 'area_km2', round(area_km2::numeric, 1),
         'i_sjo', i_sjo, 'url', 'https://www.openstreetmap.org/' || ext_id, 'kalla', 'OpenStreetMap')) as egenskaper
from import.osm_oar where rang <= 300;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'OE', 'geografi', 'Ö', ext_id, namn, geom, egenskaper, now() from oe
on conflict (kalla, ext_id) do update
  set kategori = excluded.kategori, typ = excluded.typ, namn = excluded.namn, geom = excluded.geom,
      egenskaper = excluded.egenskaper, uppdaterad = now();

select * from public.objekt_stada(array['OE'], (select array_agg('OE:' || ext_id) from oe));
drop table import.osm_oar, import.osm_oar_linjer;
commit;

select count(*) as oar, pg_size_pretty(sum(pg_column_size(geom))) as geometri from public.objekt where kalla = 'OE' and not (egenskaper ? 'utgatt');

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
