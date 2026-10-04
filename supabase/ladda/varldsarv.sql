-- Flyttar världsarv från import.varldsarv (laddad med ogr2ogr) till public.objekt.
-- Delområden med samma namn slås ihop till ett objekt per världsarv.
\set ON_ERROR_STOP on
begin;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'VA', 'kultur', 'Världsarv', sitename_sve, sitename_sve,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(geom))), 3)),
       jsonb_build_object('namn_en', max(sitename_eng), 'unesco', max(unesco_href), 'ar', max(legalfoundationyear), 'delar', count(*)),
       now()
from import.varldsarv
where sitename_sve is not null
group by sitename_sve
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

-- Ta bort världsarv som inte längre finns i källan
delete from public.objekt o
where o.kalla = 'VA' and not exists (select 1 from import.varldsarv i where i.sitename_sve = o.ext_id);

drop table import.varldsarv;
commit;

select count(*) as varldsarv, pg_size_pretty(sum(pg_column_size(geom))) as geometri from public.objekt where kalla = 'VA';
