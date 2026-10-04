-- Kyrkobyggnader (KY) och fyrar (FY) ur import.bebyggelse (ogr2ogr) till public.objekt.
-- Kyrkor: bara kyrkobyggnader (inte kyrkotomter, begravningsplatser m.m.).
-- Fyrar: bara själva fyren – även när fyren sitter ihop med fyrvaktarbostaden (då är "fyr" huvud- eller sekundärt ändamål),
--        men inte rena bostäder, uthus, förråd m.m. på fyrplatsen.
\set ON_ERROR_STOP on
begin;

create temp table b as
select to_jsonb(t) - 'geom' - 'ogc_fid' as j, ST_MakeValid(t.geom) as geom from import.bebyggelse t where t.geom is not null;

-- Kontroll: vilka värden finns? (visas i utskriften så att urvalet kan justeras)
\pset pager off
select 'kyrkligt_kulturminnestyp' as falt, j->>'kyrkligt_kulturminnestyp_namn' as varde, count(*)
from b where j->>'kyrkligt_kulturminnestyp_namn' is not null group by 1, 2
union all
select 'andamal (fyr)', coalesce(j->>'andamal_underkategori', '-') || ' / ' || coalesce(j->>'sekundart_andamal', '-'), count(*)
from b where concat_ws(' ', j->>'andamal_underkategori', j->>'sekundart_andamal') ~* 'fyr'
group by 1, 2 order by 1, 3 desc;

create temp table ut as
select 'KY' as kalla, 'Kyrka' as typ, j, geom from b
where (j->>'kyrkligt_kulturminnestyp_namn') ~* 'kyrkobyggnad|^kyrka'
union all
select 'FY', 'Fyr', j, geom from b
-- Huvudändamål som slutar på -fyr (Fyr, Ledfyr, Angöringsfyr, Hamnfyr …) men inte Fyrvaktarbostad/Fyrmästarbostad,
-- eller sekundärt ändamål med ett värde som slutar på -fyr ("Fyr", "Ledfyr" …) = fyr ihopbyggd med t.ex. bostad.
where coalesce(j->>'andamal_underkategori', '') ~* 'fyr$'
   or coalesce(j->>'sekundart_andamal', '')     ~* '"[^"]*fyr"';

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select kalla, 'kultur', typ, j->>'id',
       coalesce(nullif(trim(j->>'namn'), ''), typ),
       ST_SimplifyPreserveTopology(geom, 0.00001),
       jsonb_strip_nulls(jsonb_build_object(
         'kommun', j->>'kommunnamn', 'lan', j->>'lansnamn', 'andamal', j->>'andamal_underkategori',
         'skydd', j->>'skyddstyp_namn', 'kyrkligt', j->>'kyrkligt_kulturminnestyp_namn',
         'nummer', j->>'bebyggelsenummer', 'url', j->>'url')),
       now()
from ut where j->>'id' is not null
on conflict (kalla, ext_id) do update
  set namn = excluded.namn, geom = excluded.geom, egenskaper = excluded.egenskaper, uppdaterad = now();

delete from public.objekt o
where o.kalla in ('KY', 'FY') and not exists (select 1 from ut where ut.kalla = o.kalla and ut.j->>'id' = o.ext_id);

drop table import.bebyggelse;
commit;

select kalla, typ, count(*) as antal from public.objekt where kalla in ('KY', 'FY') group by 1, 2;
