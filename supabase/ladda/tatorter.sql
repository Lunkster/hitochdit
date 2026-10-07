-- Flyttar de 300 största tätorterna från import.scb_tatorter (ogr2ogr) till public.objekt (kalla = TA, kategori geografi).
-- ext_id = SCB:s tätortskod. Rang (1–300) efter folkmängd sparas i egenskaper.
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table ta as
select t.tatortskod as ext_id, t.tatort as namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(t.geom), 3)) as geom,
       jsonb_strip_nulls(jsonb_build_object(
         'rang', row_number() over (order by t.bef desc, t.tatort), 'lista', 300,
         'folkmangd', t.bef, 'ar', t.ar, 'area_ha', t.area_ha,
         'kommun', t.kommunnamn, 'kommunkod', t.kommun, 'lan', t.lannamn)) as egenskaper
from import.scb_tatorter t
where t.tatortskod is not null;

delete from ta where geom is null or ST_IsEmpty(geom);

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'TA', 'geografi', 'Tätort', ext_id, namn, geom, egenskaper, now() from ta
on conflict (kalla, ext_id) do update
  set kategori = excluded.kategori, typ = excluded.typ, namn = excluded.namn, geom = excluded.geom,
      egenskaper = excluded.egenskaper, uppdaterad = now();

-- Tätorter som fallit ur listan: tas bort, eller markeras utgångna om någon besökt dem
select * from public.objekt_stada(array['TA'], (select array_agg('TA:' || ext_id) from ta));

drop table import.scb_tatorter;
commit;

select count(*) filter (where not (egenskaper ? 'utgatt')) as tatorter, count(*) filter (where egenskaper ? 'utgatt') as utgangna,
       pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.objekt where kalla = 'TA';
select (egenskaper->>'rang')::int as rang, namn, egenskaper->>'kommun' as kommun, (egenskaper->>'folkmangd')::int as folkmangd
from public.objekt where kalla = 'TA' and (egenskaper->>'rang')::int in (1, 2, 3, 100, 200, 299, 300) order by 1;

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
