-- Flyttar naturminnen från import.nv_nm (ogr2ogr) till public.objekt (kalla = NM, kategori natur). ext_id = NVR-id.
-- Många heter bara "Ek", "Bok" eller "Flyttblock" – namn som finns flera gånger får kommunen inom parentes: "Ek (Borgholm)".
-- Kommun och län saknas i NV:s data för naturminnen och tas därför från Lantmäteriets indelning.
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table nm as
select r.j->>'nvrid' as ext_id,
       coalesce(nullif(trim(max(r.j->>'namn')), ''), 'Naturminne') as namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(r.geom))), 3)) as geom,
       jsonb_strip_nulls(jsonb_build_object(
         'beslut',     max(r.j->>'urspr_beslutsdatum'),
         'status',     max(r.j->>'beslutsstatus'),
         'forvaltare', max(coalesce(r.j->>'förvaltare', r.j->>'forvaltare')),
         'area_ha',    max((r.j->>'area_ha')::numeric))) as egenskaper
from (select to_jsonb(t) - 'geom' - 'ogc_fid' as j, t.geom from import.nv_nm t) r
where r.j->>'nvrid' is not null
  and coalesce(r.j->>'beslutsstatus', '') not ilike '%upph%'
group by r.j->>'nvrid';

delete from nm where geom is null or ST_IsEmpty(geom);

-- Kommun och län ur Lantmäteriets indelning (närmaste kommun inom 25 km)
alter table nm add column kommun text, add column lan text;
update nm set (kommun, lan) = (
  select i.kortnamn, l.namn
  from public.indelning i left join public.indelning l on l.typ = 'lan' and l.kod = i.lanskod
  where i.typ = 'kommun' and i.geom && ST_Expand(ST_PointOnSurface(nm.geom), 0.5)
    and ST_DWithin(i.geom::geography, ST_PointOnSurface(nm.geom)::geography, 25000)
  order by ST_Distance(i.geom::geography, ST_PointOnSurface(nm.geom)::geography) limit 1);

-- Dubbla namn får kommunen inom parentes
update nm set namn = nm.namn || ' (' || nm.kommun || ')'
where nm.kommun is not null and (select count(*) from nm n2 where lower(n2.namn) = lower(nm.namn)) > 1;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'NM', 'natur', 'Naturminne', ext_id, namn, geom,
       egenskaper || jsonb_strip_nulls(jsonb_build_object('kommun', kommun, 'lan', lan)), now()
from nm
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

-- Naturminnen som försvunnit: tas bort, eller markeras utgångna om någon besökt dem
select * from public.objekt_stada(array['NM'], (select array_agg('NM:' || ext_id) from nm));

drop table import.nv_nm;
commit;

select count(*) as naturminnen, count(*) filter (where egenskaper ? 'kommun') as med_kommun,
       pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.objekt where kalla = 'NM' and not (egenskaper ? 'utgatt');
-- Vanligaste namnen före kommuntillägget
select regexp_replace(namn, ' \(.*\)$', '') as namn, count(*) as antal
from public.objekt where kalla = 'NM' group by 1 order by 2 desc limit 10;
