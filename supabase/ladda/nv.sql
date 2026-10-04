-- Flyttar naturreservat (NR), nationalparker (NP) och kulturreservat (KR) från import.nv_* (ogr2ogr) till public.objekt.
-- ext_id = NVR-id. Geometrin förenklas (~4 m) för att hålla nere storleken. Upphävda beslut tas inte med.
-- Fält läses via to_jsonb så att det inte spelar någon roll hur ogr2ogr skrivit kolumnnamn med å/ä/ö.
\set ON_ERROR_STOP on
begin;

create temp table nv as
with radata as (
  select 'NR' as kalla, to_jsonb(t) - 'geom' - 'ogc_fid' as j, t.geom from import.nv_nr t
  union all
  select 'NP', to_jsonb(t) - 'geom' - 'ogc_fid', t.geom from import.nv_np t
  union all
  select 'KR', to_jsonb(t) - 'geom' - 'ogc_fid', t.geom from import.nv_kr t
)
select r.kalla, k.kategori, k.typ,
       r.j->>'nvrid' as ext_id,
       coalesce(nullif(trim(max(r.j->>'namn')), ''), k.typ) as namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(
         ST_SimplifyPreserveTopology(ST_Union(ST_MakeValid(r.geom)), 0.00004)), 3)) as geom,
       jsonb_strip_nulls(jsonb_build_object(
         'kommun',      max(coalesce(r.j->>'kommun', '')),
         'lan',         max(coalesce(r.j->>'län', r.j->>'lan', '')),
         'iucn',        max(r.j->>'iucnkategori'),
         'beslut',      max(r.j->>'urspr_beslutsdatum'),
         'status',      max(r.j->>'beslutsstatus'),
         'forvaltare',  max(coalesce(r.j->>'förvaltare', r.j->>'forvaltare')),
         'area_ha',     max((r.j->>'area_ha')::numeric))) as egenskaper
from radata r
join (values ('NR', 'natur',  'Naturreservat'),
             ('NP', 'natur',  'Nationalpark'),
             ('KR', 'kultur', 'Kulturreservat')) k(kalla, kategori, typ) on k.kalla = r.kalla
where r.j->>'nvrid' is not null
  and coalesce(r.j->>'beslutsstatus', '') not ilike '%upph%'
group by r.kalla, k.kategori, k.typ, r.j->>'nvrid';

delete from nv where geom is null or ST_IsEmpty(geom);

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select kalla, kategori, typ, ext_id, namn, geom, egenskaper, now() from nv
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

delete from public.objekt o
where o.kalla in ('NR', 'NP', 'KR')
  and not exists (select 1 from nv where nv.kalla = o.kalla and nv.ext_id = o.ext_id);

drop table import.nv_nr, import.nv_np, import.nv_kr;
commit;

select kalla, typ, count(*) as antal, pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.objekt where kalla in ('NR', 'NP', 'KR') group by kalla, typ order by kalla;
