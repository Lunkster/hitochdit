-- Flyttar byggnadsminnen från import.byggnadsminnen (ogr2ogr) till public.objekt.
-- Tar med enskilda och statliga byggnadsminnen; hävda skydd (havt_skydd = true) tas bort.
\set ON_ERROR_STOP on
begin;

create temp table bm as
select id::text as ext_id,
       coalesce(nullif(trim(namn), ''), 'Byggnadsminne') as namn,
       ST_MakeValid(geom) as geom,
       jsonb_strip_nulls(jsonb_build_object(
         'statligt',   skyddstyp_id = 'STATLIGT_BYGGNADSMINNE',
         'skyddstyp',  skyddstyp_namn,
         'beslut',     beslutsdatum::text,
         'kommun',     kommunnamn,
         'lan',        lansnamn,
         'andamal',    coalesce(andamal_underkategori, andamal_huvudkategori),
         'nummer',     bebyggelsenummer,
         'url',        url)) as egenskaper
from import.byggnadsminnen
where coalesce(havt_skydd::text, 'false') not in ('true', '1', 't')
  and geom is not null;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'BM', 'kultur', 'Byggnadsminne', ext_id, namn, geom, egenskaper, now() from bm
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

delete from public.objekt o
where o.kalla = 'BM' and not exists (select 1 from bm where bm.ext_id = o.ext_id);

drop table import.byggnadsminnen;
commit;

select count(*) as byggnadsminnen,
       count(*) filter (where (egenskaper->>'statligt')::boolean) as varav_statliga,
       pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.objekt where kalla = 'BM';
