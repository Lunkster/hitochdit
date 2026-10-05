-- Flyttar de 300 största insjöarna från import.smhi_vattenytor (ogr2ogr) till public.objekt (kalla = SJ, kategori geografi).
-- Vattenytor med samma SJOID slås ihop till en sjö. ext_id = SJOID. Rang (1–300) efter area sparas i egenskaper.
-- Fält läses via to_jsonb så att det inte spelar någon roll om kolumnerna heter SJOID eller sjoid.
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table yta as
select coalesce(nullif(trim(coalesce(j->>'sjoid', j->>'SJOID')), ''), coalesce(j->>'vyid', j->>'VYID')) as sjoid,
       nullif(trim(coalesce(j->>'name', j->>'NAME')), '') as namn,
       coalesce(j->>'ytkod', j->>'YTKOD') as ytkod,
       coalesce(j->>'country', j->>'COUNTRY') as land,
       (coalesce(j->>'vyhojd', j->>'VYHOJD'))::numeric as hojd,
       ST_MakeValid(geom) as geom
from (select to_jsonb(t) - 'geom' as j, t.geom from import.smhi_vattenytor t) x;

delete from yta where ytkod not in ('50', '51') or geom is null or ST_IsEmpty(geom);

create temp table sjo as
select sjoid as ext_id,
       (array_agg(namn order by ST_Area(geom::geography) desc) filter (where namn is not null))[1] as namn,
       sum(ST_Area(geom::geography)) / 1e6 as area_km2,
       count(*) as delar, max(hojd) as hojd, bool_or(land is distinct from 'SE') as utland
from yta group by sjoid;

create temp table topp as
select s.*, row_number() over (order by s.area_km2 desc, s.ext_id) as rang
from sjo s order by s.area_km2 desc limit 300;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'SJ', 'geografi', 'Sjö', t.ext_id, coalesce(t.namn, 'Namnlös sjö'),
       (select ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(y.geom)), 3)) from yta y where y.sjoid = t.ext_id),
       jsonb_strip_nulls(jsonb_build_object('rang', t.rang, 'lista', 300, 'area_km2', round(t.area_km2::numeric, 1),
         'hojd', t.hojd, 'delar', t.delar, 'utland', nullif(t.utland, false), 'kalla', 'SMHI SVAR 2016')),
       now()
from topp t
on conflict (kalla, ext_id) do update
  set kategori = excluded.kategori, typ = excluded.typ, namn = excluded.namn, geom = excluded.geom,
      egenskaper = excluded.egenskaper, uppdaterad = now();

-- Sjöar som fallit ur listan: tas bort, eller markeras utgångna om någon besökt dem
select * from public.objekt_stada(array['SJ'], (select array_agg('SJ:' || ext_id) from topp));

drop table import.smhi_vattenytor;
commit;

select count(*) filter (where not (egenskaper ? 'utgatt')) as sjoar, count(*) filter (where egenskaper ? 'utgatt') as utgangna,
       pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.objekt where kalla = 'SJ';
-- Kontroll: topp 10, gränsen vid 300, namnlösa och namn som förekommer flera gånger (kan vara en sjö som är uppdelad på flera SJOID)
select (egenskaper->>'rang')::int as rang, namn, egenskaper->>'area_km2' as km2, egenskaper->>'delar' as delar
from public.objekt where kalla = 'SJ' and ((egenskaper->>'rang')::int <= 10 or (egenskaper->>'rang')::int >= 298) order by 1;
select namn, count(*) as antal, string_agg(egenskaper->>'rang', ', ' order by (egenskaper->>'rang')::int) as rang
from public.objekt where kalla = 'SJ' group by namn having count(*) > 1 or namn = 'Namnlös sjö' order by 2 desc, 1;
