-- Punkter för objekt inom kartutsnittet – används för att rita kyrkor och fyrar som symboler i kartan.
-- Kör i SQL Editor. Går att köra om.
create or replace function public.objekt_i_ruta(kallor text[], vast double precision, syd double precision,
                                                ost double precision, norr double precision, max_antal int default 1500)
returns table (kalla text, typ text, ext_id text, namn text, url text, lat double precision, lon double precision)
language sql stable set search_path = public, extensions as $$
  select o.kalla, o.typ, o.ext_id, o.namn, coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         ST_Y(ST_PointOnSurface(o.geom)), ST_X(ST_PointOnSurface(o.geom))
  from public.objekt o
  where o.kalla = any(kallor)
    and o.geom && ST_MakeEnvelope(vast, syd, ost, norr, 4326)
  limit least(coalesce(max_antal, 1500), 5000);
$$;
grant execute on function public.objekt_i_ruta(text[], double precision, double precision, double precision, double precision, int) to anon, authenticated;
