-- Flyttar kommuner och län från import.lm_kommun / import.lm_lan (ogr2ogr) till public.indelning
-- och fyller i kommun/län på alla befintliga besök.
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table ny as
select 'kommun' as typ, kommunkod as kod, beslutatnamn as namn, namnkortform as kortnamn, lanskod, null::text as lansbokstav, geom
from import.lm_kommun
union all
select 'lan', lanskod, beslutatnamn, namnkortform, lanskod, trim(lansbokstav), geom
from import.lm_lan;

insert into public.indelning (typ, kod, namn, kortnamn, lanskod, lansbokstav, geom, uppdaterad)
select typ, kod, namn, kortnamn, lanskod, lansbokstav,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_SimplifyPreserveTopology(ST_MakeValid(geom), 0.0001)), 3)), now()
from ny
on conflict (typ, kod) do update
  set namn = excluded.namn, kortnamn = excluded.kortnamn, lanskod = excluded.lanskod,
      lansbokstav = excluded.lansbokstav, geom = excluded.geom, uppdaterad = now();

delete from public.indelning i where not exists (select 1 from ny where ny.typ = i.typ and ny.kod = i.kod);

drop table import.lm_kommun, import.lm_lan;

-- Fyll i kommun/län på befintliga besök (triggern körs vid update)
update public.besok set scheme = scheme;
commit;

select typ, count(*) as antal, pg_size_pretty(sum(pg_column_size(geom))) as geometri from public.indelning group by typ;
select count(*) as besok, count(kommunkod) as med_kommun from public.besok;
