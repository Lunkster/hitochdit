-- Slott och herrgårdar (SH) ur import.sh_bm och import.sh_beb (ogr2ogr, tools/ladda_slott.sh) till public.objekt.
-- RAÄ har ingen egen herrgårdskategori på byggnader (herrgårdar är "Mangårdsbyggnad", som vanliga gårdars huvudbyggnader).
-- Däremot har byggnadsminnenas skyddsområden ändamålet Slottsmiljö, Herrgårdsmiljö eller Kungsgård. Urval:
--   1. Byggnadsminnen (skyddsområden) med Slottsmiljö, Herrgårdsmiljö eller Kungsgård.
--   2. Andra byggnadsminnen som innehåller en byggnad med ändamålet Slott, eller en mangårdsbyggnad som heter
--      något med herrgård/slott/säteri (t.ex. Svartsjö slott, Nyköpingshus, bruksherrgårdar). Ett objekt per skyddsområde.
--   3. Fristående byggnader och miljöer (inget gällande byggnadsminne) av samma slag, med namn. Samma namn i samma
--      kommun slås ihop (t.ex. Farsta slott: byggnad + miljö).
-- Palats tas inte med (stadspalats och stenvillor). Ett slott som är byggnadsminne finns också som BM – två samlingar
-- (beslut 2026-10-09). Nyckel (ext_id) = RAÄ:s id för skyddsområdet resp. byggnaden.
\set ON_ERROR_STOP on
begin;

create temp table bm as
select id, nullif(trim(namn), '') as namn, andamal_underkategori as miljo, skyddstyp_namn as skydd,
       kommunnamn as kommun, lansnamn as lan, url, ST_MakeValid(geom) as geom
from import.sh_bm where geom is not null and id is not null;

create temp table kand as
select id, nullif(trim(namn), '') as namn, andamal_huvudkategori as hk, andamal_underkategori as uk, skyddstyp_namn as skydd,
       substring(ingar_i from '([0-9a-f-]{36})$') as bm_id, kommunnamn as kommun, lansnamn as lan, url, ST_MakeValid(geom) as geom
from import.sh_beb
where geom is not null and id is not null
  and (andamal_huvudkategori = 'Slott' or andamal_underkategori in ('Herrgårdsmiljö', 'Slottsmiljö')
       or namn ~* '(herrgård|slott|säteri)');

\pset pager off
select 'kandidatbyggnader' as vad, count(*) from kand
union all select 'i valt byggnadsminne', count(*) from kand k join bm on bm.id = k.bm_id
union all select 'fristående', count(*) from kand k where not exists (select 1 from bm where bm.id = k.bm_id);

create temp table sh as
select bm.id as ext_id, coalesce(bm.namn, 'Herrgård') as namn,
       case when bm.miljo = 'Kungsgård' then 'Kungsgård'
            when bm.miljo = 'Slottsmiljö' or bm.namn ~* '(slott|borg\M|hus$|citadell)'
              or exists (select 1 from kand k where k.bm_id = bm.id and (k.hk = 'Slott' or k.namn ~* 'slott')) then 'Slott'
            else 'Herrgård' end as typ,
       bm.skydd, bm.kommun, bm.lan, bm.url, bm.miljo, bm.geom
from bm
where bm.miljo in ('Slottsmiljö', 'Herrgårdsmiljö', 'Kungsgård')
   or exists (select 1 from kand k where k.bm_id = bm.id)
union all
select min(k.id),
       case when lower(k.namn) in ('herrgård', 'herrgården', 'slott', 'slottet') then k.namn || ', ' || k.kommun else k.namn end,
       case when bool_or(k.hk = 'Slott' or k.namn ~* 'slott') then 'Slott' else 'Herrgård' end,
       min(k.skydd), k.kommun, min(k.lan), min(k.url), min(k.uk), ST_Union(k.geom)
from kand k
where k.namn is not null and not exists (select 1 from bm where bm.id = k.bm_id)
group by k.namn, k.kommun;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'SH', 'kultur', typ, ext_id, namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_SimplifyPreserveTopology(geom, 0.00001)), 3)),
       jsonb_strip_nulls(jsonb_build_object('kommun', kommun, 'lan', lan, 'skydd', skydd, 'miljo', miljo, 'url', url)),
       now()
from sh
where not ST_IsEmpty(ST_CollectionExtract(geom, 3))
on conflict (kalla, ext_id) do update
  set typ = excluded.typ, namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

-- Slott/herrgårdar som inte längre finns i källan: tas bort, eller markeras utgångna om någon besökt dem
select * from public.objekt_stada(array['SH'], (select array_agg('SH:' || ext_id) from sh));

drop table import.sh_bm;
drop table import.sh_beb;
commit;

select typ, count(*) as antal, count(*) filter (where egenskaper->>'skydd' ilike '%byggnadsminne') as byggnadsminnen
from public.objekt where kalla = 'SH' and not (egenskaper ? 'utgatt') group by 1 order by 2 desc;

-- Märkenas totaler (22_marken.sql) räknas om efter varje laddning
select public.marke_totaler_uppdatera() as marke_grupper;
