-- Flyttar fornlämningar från import.fl_punkt/fl_linje/fl_yta (ogr2ogr) till public.objekt (kalla = FL).
-- Bara antikvarisk bedömning "Fornlämning" (filtreras även här ifall servern inte kunde filtrera).
-- ext_id = lämningsnummer (t.ex. L1969:3430). Ytor och linjer förenklas (~2 m).
-- Kommun/län sparas inte (tar plats för 300 000 objekt) – kommer från Lantmäteriets indelning.
\set ON_ERROR_STOP on
begin;

create temp table fl as
with radata as (
  select to_jsonb(t) - 'geom' - 'ogc_fid' as j, t.geom from import.fl_punkt t
  union all select to_jsonb(t) - 'geom' - 'ogc_fid', t.geom from import.fl_linje t
  union all select to_jsonb(t) - 'geom' - 'ogc_fid', t.geom from import.fl_yta t
)
select coalesce(nullif(j->>'lamningsnummer', ''), j->>'pk_id') as ext_id,
       coalesce(nullif(trim(max(j->>'lamningsnamn')), ''),
                max(j->>'lamningstyp') || coalesce(' (' || max(j->>'raa_nummer') || ')', ''),
                'Fornlämning') as namn,
       (case when count(*) = 1 then (array_agg(g))[1] else ST_Collect(g) end) as geom,
       jsonb_strip_nulls(jsonb_build_object(
         'lamningstyp', max(j->>'lamningstyp'),
         'raa_nummer',  max(j->>'raa_nummer'),
         'url',         max(j->>'url'))) as egenskaper
from (select j, case when GeometryType(geom) ilike '%POINT%' then geom
                    else ST_SimplifyPreserveTopology(ST_MakeValid(geom), 0.00002) end as g, geom
      from radata) r
where coalesce(j->>'antikvariskbedomning', '') ilike 'fornl%'
  and geom is not null
group by 1;

delete from fl where ext_id is null or geom is null or ST_IsEmpty(geom);

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'FL', 'kultur', 'Fornlämning', ext_id, namn, geom, egenskaper, now() from fl
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

delete from public.objekt o
where o.kalla = 'FL' and not exists (select 1 from fl where fl.ext_id = o.ext_id);

drop table import.fl_punkt, import.fl_linje, import.fl_yta;
commit;

select count(*) as fornlamningar, pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.objekt where kalla = 'FL';
-- Vanligaste lämningstyperna
select egenskaper->>'lamningstyp' as lamningstyp, count(*) from public.objekt where kalla = 'FL'
group by 1 order by 2 desc limit 15;

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
