-- Flyttar socknar och städer från import.lm_sockenstad (ogr2ogr) till public.indelning (typ = 'socken')
-- och fyller i socken på alla befintliga besök. kod = sockenstadkod (4 siffror). Delområden slås ihop per kod.
-- Fält läses via to_jsonb så att det inte spelar någon roll om kolumnerna har versaler.
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table s as
select coalesce(j->>'sockenstadkod', j->>'SOCKENSTADKOD') as kod,
       trim(coalesce(j->>'sockenstadnamn', j->>'SOCKENSTADNAMN')) as kortnamn,
       case coalesce(j->>'sockenstadtyp', j->>'SOCKENSTADTYP') when '2' then 'stad' else 'socken' end as undertyp,
       geom
from (select to_jsonb(t) - 'geom' as j, t.geom from import.lm_sockenstad t) x;

create temp table ny as
select kod, max(kortnamn) as kortnamn, max(undertyp) as undertyp,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(geom))), 3)) as geom
from s where kod is not null group by kod;
delete from ny where geom is null or ST_IsEmpty(geom);

-- Länet där sockenns största del ligger (ur Lantmäteriets län i samma tabell)
alter table ny add column lanskod text;
update ny set lanskod = (select l.kod from public.indelning l
                         where l.typ = 'lan' and l.geom && ny.geom and ST_Intersects(l.geom, ST_PointOnSurface(ny.geom)) limit 1);

insert into public.indelning (typ, kod, namn, kortnamn, undertyp, lanskod, geom, uppdaterad)
select 'socken', kod, kortnamn || case undertyp when 'stad' then ' stad' else ' socken' end, kortnamn, undertyp, lanskod, geom, now()
from ny
on conflict (typ, kod) do update
  set namn = excluded.namn, kortnamn = excluded.kortnamn, undertyp = excluded.undertyp,
      lanskod = excluded.lanskod, geom = excluded.geom, uppdaterad = now();

delete from public.indelning i where i.typ = 'socken' and not exists (select 1 from ny where ny.kod = i.kod);

drop table import.lm_sockenstad;

-- Fyll i socken på befintliga besök (triggern körs vid update)
update public.besok set scheme = scheme;
commit;

select undertyp, count(*) as antal, count(lanskod) as med_lan, pg_size_pretty(sum(pg_column_size(geom))) as geometri
from public.indelning where typ = 'socken' group by undertyp;
select count(*) as besok, count(sockenkod) as med_socken from public.besok;

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
