-- Toppar (kalla = TO): rangtext i svaren och 75 m radie (man står på toppen, inte exakt på punkten). Kör i SQL Editor
-- INNAN tools/ladda_toppar.sh. Går att köra om.
drop function if exists public.objekt_vid(double precision, double precision, double precision, text[]);
create function public.objekt_vid(lat double precision, lon double precision,
                                  radie_m double precision default 25, kallor text[] default null)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision, url text,
               rang int, lista int, rangtext text)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt,
                    greatest(coalesce(radie_m, 0), 0) as r)
  select o.kalla, o.kategori, o.typ, o.ext_id, o.namn,
         round(ST_Distance(o.geom::geography, p.pt::geography)::numeric, 1)::double precision,
         coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         (o.egenskaper->>'rang')::int, (o.egenskaper->>'lista')::int, o.egenskaper->>'rangtext'
  from public.objekt o, p
  where o.geom && ST_Expand(p.pt, greatest(p.r, 75) / 30000.0)
    and ST_DWithin(o.geom::geography, p.pt::geography,
                   case o.kalla when 'SJ' then greatest(p.r, 50) when 'TO' then greatest(p.r, 75) else p.r end)
    and (kallor is null or o.kalla = any(kallor))
    and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  order by 6, o.namn
  limit 50;
$$;
grant execute on function public.objekt_vid(double precision, double precision, double precision, text[]) to anon, authenticated;

-- Symboler i kartan behöver också rangtexten
drop function if exists public.objekt_i_ruta(text[], double precision, double precision, double precision, double precision, int);
create function public.objekt_i_ruta(kallor text[], vast double precision, syd double precision,
                                     ost double precision, norr double precision, max_antal int default 1500)
returns table (kalla text, typ text, ext_id text, namn text, url text, lat double precision, lon double precision, rangtext text)
language sql stable set search_path = public, extensions as $$
  select o.kalla, o.typ, o.ext_id, o.namn, coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         ST_Y(ST_PointOnSurface(o.geom)), ST_X(ST_PointOnSurface(o.geom)), o.egenskaper->>'rangtext'
  from public.objekt o
  where o.kalla = any(kallor)
    and o.geom && ST_MakeEnvelope(vast, syd, ost, norr, 4326)
    and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  limit least(coalesce(max_antal, 1500), 5000);
$$;
grant execute on function public.objekt_i_ruta(text[], double precision, double precision, double precision, double precision, int) to anon, authenticated;
