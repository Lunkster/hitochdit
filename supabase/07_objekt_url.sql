-- Lägger till länk (url) till källans objektsida i svaren från objekt_vid och objekt_geom.
-- Kör i SQL Editor efter 06_geodata.sql. Går att köra om.

drop function if exists public.objekt_vid(double precision, double precision, double precision, text[]);
create function public.objekt_vid(lat double precision, lon double precision,
                                  radie_m double precision default 25, kallor text[] default null)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision, url text)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography g)
  select o.kalla, o.kategori, o.typ, o.ext_id, o.namn,
         round(ST_Distance(o.geom::geography, p.g)::numeric, 1)::double precision,
         coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco')
  from public.objekt o, p
  where ST_DWithin(o.geom::geography, p.g, greatest(coalesce(radie_m, 0), 0))
    and (kallor is null or o.kalla = any(kallor))
  order by 6, o.namn
  limit 50;
$$;

drop function if exists public.objekt_geom(text[]);
create function public.objekt_geom(nycklar text[])
returns table (kalla text, ext_id text, typ text, namn text, url text, geojson json)
language sql stable set search_path = public, extensions as $$
  select o.kalla, o.ext_id, o.typ, o.namn, coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         ST_AsGeoJSON(ST_SimplifyPreserveTopology(o.geom, 0.00003), 6)::json
  from public.objekt o
  where (o.kalla || ':' || o.ext_id) = any(nycklar)
  limit 500;
$$;

grant execute on function public.objekt_vid(double precision, double precision, double precision, text[]) to anon, authenticated;
grant execute on function public.objekt_geom(text[]) to anon, authenticated;
