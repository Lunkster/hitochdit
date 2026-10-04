-- Minskar geodatabasens storlek efter att fornlämningarna laddats (~319 000 objekt).
-- 1) Positionsfrågan använder geometri-indexet i stället för ett eget geografi-index (som tar mycket plats).
-- 2) Kommun/län tas bort ur fornlämningarnas egenskaper (kommer från Lantmäteriets indelning senare).
-- 3) Platsen lämnas tillbaka med tools/geodata_stada.sh (VACUUM kan inte köras i SQL Editor).
-- Kör filen i SQL Editor. Går att köra om.

drop function if exists public.objekt_vid(double precision, double precision, double precision, text[]);
create function public.objekt_vid(lat double precision, lon double precision,
                                  radie_m double precision default 25, kallor text[] default null)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision, url text)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt,
                    greatest(coalesce(radie_m, 0), 0) as r)
  select o.kalla, o.kategori, o.typ, o.ext_id, o.namn,
         round(ST_Distance(o.geom::geography, p.pt::geography)::numeric, 1)::double precision,
         coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco')
  from public.objekt o, p
  where o.geom && ST_Expand(p.pt, p.r / 30000.0)              -- grovsållning med geometri-indexet (30 km per grad räcker i hela Sverige)
    and ST_DWithin(o.geom::geography, p.pt::geography, p.r)    -- exakt avstånd i meter
    and (kallor is null or o.kalla = any(kallor))
  order by 6, o.namn
  limit 50;
$$;
grant execute on function public.objekt_vid(double precision, double precision, double precision, text[]) to anon, authenticated;

drop index if exists public.objekt_geog_idx;

update public.objekt set egenskaper = egenskaper - 'kommun' - 'lan'
where kalla = 'FL' and (egenskaper ? 'kommun' or egenskaper ? 'lan');

select pg_size_pretty(pg_total_relation_size('public.objekt')) as objekt_inkl_index,
       pg_size_pretty(pg_database_size(current_database())) as hela_databasen;
