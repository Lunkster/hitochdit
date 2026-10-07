-- Flyttar landskap från import.landskap (ogr2ogr) till public.indelning (typ = 'landskap', kod = landskapets namn)
-- och fyller i landskap på alla besök. Namnfältet läses via to_jsonb (heter olika i olika versioner av filen).
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table ny as
select trim(coalesce(j->>'landskap', j->>'name', j->>'namn', j->>'NAMN', j->>'Landskap')) as namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(geom))), 3)) as geom
from (select to_jsonb(t) - 'geom' - 'ogc_fid' as j, t.geom from import.landskap t) x
group by 1;
delete from ny where namn is null or geom is null or ST_IsEmpty(geom);

-- Länet där landskapets största del ligger (Lappland och Västergötland m.fl. delas av flera län – bara som upplysning)
insert into public.indelning (typ, kod, namn, kortnamn, lanskod, geom, uppdaterad)
select 'landskap', ny.namn, ny.namn, ny.namn,
       (select l.kod from public.indelning l where l.typ = 'lan' and l.geom && ny.geom
        order by ST_Area(ST_Intersection(l.geom, ny.geom)) desc limit 1),
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_SimplifyPreserveTopology(ny.geom, 0.0001)), 3)), now()
from ny
on conflict (typ, kod) do update
  set namn = excluded.namn, kortnamn = excluded.kortnamn, lanskod = excluded.lanskod, geom = excluded.geom, uppdaterad = now();
delete from public.indelning i where i.typ = 'landskap' and not exists (select 1 from ny where ny.namn = i.kod);

drop table import.landskap;
update public.besok set scheme = scheme;   -- triggern fyller i landskap
commit;

select count(*) as landskap, pg_size_pretty(sum(pg_column_size(geom))) as geometri from public.indelning where typ = 'landskap';
select kod as landskap, round((ST_Area(geom::geography) / 1e6)::numeric) as km2_inkl_vatten from public.indelning where typ = 'landskap' order by 2 desc;
select count(*) as besok, count(landskap) as med_landskap from public.besok;

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
