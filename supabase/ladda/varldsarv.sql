-- Flyttar världsarv från import.varldsarv (laddad med ogr2ogr) till public.objekt.
-- Nyckel (ext_id) = UNESCO-nummer ur unesco_href (…/list/555) – tål namnbyten (sedan 2026-10-08, 23_varldsarv_unesco.sql).
-- Delområden med samma UNESCO-nummer slås ihop till ett objekt per världsarv.
\set ON_ERROR_STOP on
begin;

create temp table va as
select substring(unesco_href from '/list/([0-9]+)') as nr, *
from import.varldsarv where sitename_sve is not null;
delete from va where nr is null;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'VA', 'kultur', 'Världsarv', nr, max(sitename_sve),
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(geom))), 3)),
       jsonb_build_object('namn_en', max(sitename_eng), 'url', max(unesco_href), 'ar', max(legalfoundationyear), 'delar', count(*)),
       now()
from va
group by nr
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

-- Världsarv som inte längre finns i källan: tas bort, eller markeras utgångna om någon besökt dem
select * from public.objekt_stada(array['VA'], (select array_agg(distinct 'VA:' || nr) from va));

drop table import.varldsarv;
commit;

select count(*) as varldsarv, pg_size_pretty(sum(pg_column_size(geom))) as geometri from public.objekt where kalla = 'VA';

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
