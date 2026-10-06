-- Bygger öytor ur import.osm_oar_linjer (OSM-linjer) till import.osm_oar och skriver en rapport.
-- Ändrar inget i appens tabeller. Körs av tools/ladda_osm_oar.sh.
\set ON_ERROR_STOP on
\pset pager off

drop table if exists import.osm_oar;
create table import.osm_oar as
select osm_typ || '/' || osm_id as ext_id, max(nullif(trim(namn), '')) as namn,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_BuildArea(ST_Collect(ST_GeomFromText(wkt, 4326)))), 3)) as geom
from import.osm_oar_linjer group by osm_typ, osm_id;

alter table import.osm_oar add column area_km2 double precision, add column i_sjo text, add column rang int;
update import.osm_oar set area_km2 = ST_Area(geom::geography) / 1e6 where geom is not null and not ST_IsEmpty(geom);
create index on import.osm_oar using gist (geom);

-- Samma ö inlagd två gånger (t.ex. både som enkel yta och relation): behåll den största
delete from import.osm_oar a using import.osm_oar b
where a.ext_id <> b.ext_id and a.namn is not null and lower(a.namn) = lower(b.namn)
  and (b.area_km2 > a.area_km2 or (b.area_km2 = a.area_km2 and b.ext_id < a.ext_id))
  and a.geom && b.geom and ST_Intersects(b.geom, ST_PointOnSurface(a.geom));

-- Öar som ska uteslutas för hand (t.ex. kanalöar) – lägg till rader här vid behov:
--   insert into utesluten values ('Namn', 'skäl');
-- Södertörn räknas som ö (beslut 2026-10-06), trots att den är en ö tack vare Södertälje kanal och Hammarbyleden.
create temp table utesluten (namn text, skal text);

-- "Ö-grupper": en yta som till största delen täcks av andra, mindre öar (t.ex. Värmdö = Värmdölandet + Ormingelandet …)
insert into utesluten
select a.namn, 'grupp av öar: ' || string_agg(b.namn, ', ' order by b.area_km2 desc)
from import.osm_oar a join import.osm_oar b
  on b.ext_id <> a.ext_id and b.area_km2 < a.area_km2 and b.geom && a.geom and ST_Within(ST_PointOnSurface(b.geom), a.geom)
where a.area_km2 is not null
group by a.ext_id, a.namn, a.area_km2
having count(*) >= 2 and sum(b.area_km2) >= 0.6 * a.area_km2;

-- Namnlösa öar tas inte med (går inte att visa i listan)
delete from import.osm_oar where namn is null;

\echo '=== Uteslutna ==='
select u.namn, round(o.area_km2::numeric, 1) as km2, u.skal from utesluten u join import.osm_oar o on o.namn = u.namn order by o.area_km2 desc;
delete from import.osm_oar o using utesluten u where o.namn = u.namn;

update import.osm_oar o set rang = r.rang
from (select ext_id, row_number() over (order by area_km2 desc, ext_id) as rang from import.osm_oar where area_km2 is not null) r
where r.ext_id = o.ext_id;

-- Ligger ön i någon av de 300 största sjöarna? Ön är ett hål i sjöytan, så vi jämför mot sjön med hålen igenfyllda.
create temp table sjo_hel as
select s.namn, ST_Collect(ST_MakePolygon(ST_ExteriorRing(d.geom))) as geom
from public.objekt s, lateral ST_Dump(s.geom) d where s.kalla = 'SJ' group by s.ext_id, s.namn;
update import.osm_oar o set i_sjo = s.namn
from sjo_hel s where o.rang <= 300 and s.geom && o.geom and ST_Intersects(s.geom, ST_PointOnSurface(o.geom));

\echo '=== Översikt ==='
select count(*) as oar, count(namn) as med_namn, count(*) filter (where area_km2 is null) as kunde_inte_byggas,
       round(min(area_km2) filter (where rang = 300)::numeric, 2) as km2_nr_300
from import.osm_oar;
\echo '=== Topp 30 ==='
select rang, coalesce(namn, '(namnlös)') as namn, round(area_km2::numeric, 1) as km2, i_sjo, ext_id
from import.osm_oar where rang <= 30 order by rang;
\echo '=== Gränsen vid 300 ==='
select rang, coalesce(namn, '(namnlös)') as namn, round(area_km2::numeric, 2) as km2, i_sjo from import.osm_oar where rang between 295 and 305 order by rang;
\echo '=== Kända öar – var hamnar de? (saknas = inte taggad som ö i OSM) ==='
select k.namn, o.rang, round(o.area_km2::numeric, 1) as km2
from (values ('Gotland'), ('Öland'), ('Orust'), ('Hisingen'), ('Värmdö'), ('Tjörn'), ('Fårö'), ('Ingarö'), ('Selaön'),
             ('Väddö'), ('Torsö'), ('Ven'), ('Frösön'), ('Lidingö'), ('Visingsö'), ('Adelsö'), ('Holmön'), ('Värmdölandet'),
             ('Kållandsö'), ('Södertörn')) k(namn)
left join import.osm_oar o on lower(o.namn) = lower(k.namn) and o.rang is not null
order by o.rang nulls last;
\echo '=== Sjööar bland de 300 ==='
select count(i_sjo) as sjooar, string_agg(namn || ' (' || i_sjo || ')', ', ' order by rang) filter (where rang <= 40) as de_storsta
from import.osm_oar where rang <= 300;
