-- Flyttar toppar från import.toppar (kod/Toppar.gpkg eller toppar.csv) till public.objekt (kalla = TO, kategori geografi, punkter).
-- ext_id = Lantmäteriets objektidentitet för höjdpunkten (stabil mellan leveranser).
\set ON_ERROR_STOP on
\pset pager off
begin;

create temp table t as
select objektidentitet as ext_id, namn,
       ST_Transform(ST_SetSRID(ST_MakePoint(x, y), 3006), 4326) as geom,
       jsonb_strip_nulls(jsonb_build_object(
         'hojd', hojd, 'rang', rang, 'lista', case when rang is not null then 300 end,
         'lanrang', lanrang, 'lan', lannamn, 'lanskod', lpad(lan::text, 2, '0'),
         'eget_namn', namn !~ '^Topp [0-9]+ m', 'prim30', prim30,
         'rangtext', concat_ws(' · ', hojd || ' m',
                               case when rang is not null then 'nr ' || rang || ' av 300' end,
                               case when lanrang = 1 then 'högst i ' || lannamn
                                    when lanrang is not null then 'nr ' || lanrang || ' i ' || lannamn end),
         'kalla', 'Lantmäteriet Topografi 100')) as egenskaper
from import.toppar where objektidentitet is not null;

insert into public.objekt (kalla, kategori, typ, ext_id, namn, geom, egenskaper, uppdaterad)
select 'TO', 'geografi', 'Topp', ext_id, namn, geom, egenskaper, now() from t
on conflict (kalla, ext_id) do update
  set kategori = excluded.kategori, typ = excluded.typ, namn = excluded.namn, geom = excluded.geom,
      egenskaper = excluded.egenskaper, uppdaterad = now();

select * from public.objekt_stada(array['TO'], (select array_agg('TO:' || ext_id) from t));
drop table import.toppar;
commit;

select count(*) as toppar, count(*) filter (where egenskaper ? 'rang') as i_300_listan,
       count(*) filter (where egenskaper ? 'lanrang') as i_lanslistor
from public.objekt where kalla = 'TO' and not (egenskaper ? 'utgatt');
select namn, egenskaper->>'rangtext' as rang from public.objekt where kalla = 'TO'
  and ((egenskaper->>'rang')::int <= 5 or (egenskaper->>'lanrang')::int = 1) order by (egenskaper->>'hojd')::int desc limit 30;
