-- Socknar och kommuner: kartskikt (gränser) och "Kvar i området" i I närheten.
-- Kör i SQL Editor. Går att köra om.

-- Gränser för socknar/kommuner/landskap inom kartutsnittet, förenklade efter zoom och klippta mot utsnittet.
-- lat/lon = en punkt inne i området (för namnetiketten).
create or replace function public.indelning_i_ruta(p_typ text, vast double precision, syd double precision,
                                                   ost double precision, norr double precision, tolerans double precision default 0.0005)
returns table (kod text, namn text, kortnamn text, lat double precision, lon double precision, geojson json)
language sql stable set search_path = public, extensions as $$
  with r as (select ST_MakeEnvelope(vast, syd, ost, norr, 4326) as box,
                    greatest(coalesce(tolerans, 0.0005), 0.00003) as tol)
  select i.kod, i.namn, i.kortnamn,
         ST_Y(ST_PointOnSurface(i.geom)), ST_X(ST_PointOnSurface(i.geom)),
         ST_AsGeoJSON(ST_SimplifyPreserveTopology(ST_ClipByBox2D(i.geom, ST_Expand(r.box, r.tol * 20)), r.tol), 5)::json
  from public.indelning i, r
  where i.typ = p_typ and p_typ in ('socken', 'kommun', 'landskap') and i.geom && r.box
  limit 800;
$$;
grant execute on function public.indelning_i_ruta(text, double precision, double precision, double precision, double precision, double precision) to anon, authenticated;

-- Socknar och kommuner inom radie_m från en position (den man står i först, avstånd 0).
create or replace function public.indelning_nara(lat double precision, lon double precision,
                                                 radie_m double precision default 10000, max_per_typ int default 12)
returns table (typ text, kod text, namn text, kortnamn text, avstand_m double precision)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt,
                    least(greatest(coalesce(radie_m, 10000), 100), 30000) as r),
  k as (
    select i.typ, i.kod, i.namn, i.kortnamn, ST_Distance(i.geom::geography, p.pt::geography) as d
    from public.indelning i, p
    where i.typ in ('socken', 'kommun')
      and i.geom && ST_Expand(p.pt, p.r / (111320 * cos(radians(lat))), p.r / 110574)
  ),
  n as (select k.*, row_number() over (partition by k.typ order by k.d) as nr from k, p where k.d <= p.r)
  select n.typ, n.kod, n.namn, n.kortnamn, round(n.d::numeric)::double precision
  from n where n.nr <= greatest(coalesce(max_per_typ, 12), 1)
  order by n.typ, n.d;
$$;
grant execute on function public.indelning_nara(double precision, double precision, double precision, int) to anon, authenticated;

-- Objekt i en socken eller kommun, med hur många man själv har besökt (egna besök via RLS – funktionen körs som anroparen).
-- Svar (jsonb): summa = per källa {kalla, typ, kategori, totalt, besokta}; lista = de max_per_typ närmaste per källa
-- (bara obesökta om bara_obesokta), med avstånd, riktning och närmaste punkt från lat/lon.
create or replace function public.objekt_i_omrade(p_typ text, p_kod text, lat double precision, lon double precision,
                                                  max_per_typ int default 25, bara_obesokta boolean default false)
returns jsonb
language sql stable set search_path = public, extensions as $$
  with omr as (select i.geom from public.indelning i where i.typ = p_typ and i.kod = p_kod and p_typ in ('socken', 'kommun')),
  p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt),
  o as (
    select o.kalla, o.kategori, o.typ, o.ext_id, o.namn, o.egenskaper, o.geom,
           exists (select 1 from public.besok b
                   where b.user_id = (select auth.uid())
                     and ((b.scheme = o.kalla and b.objekt_id = o.ext_id)
                          or (o.kalla in ('NR', 'NP', 'KR', 'NM') and b.nvrid = o.ext_id))) as besokt
    from public.objekt o, omr
    where o.geom && omr.geom and ST_Intersects(o.geom, omr.geom)
      and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  ),
  summa as (
    select o.kalla, min(o.typ) as typ, min(o.kategori) as kategori, count(*) as totalt, count(*) filter (where o.besokt) as besokta
    from o group by o.kalla
  ),
  rang as (
    select o.*, row_number() over (partition by o.kalla order by o.geom <-> p.pt) as nr
    from o, p where not coalesce(bara_obesokta, false) or not o.besokt
  ),
  lista as (
    select r.*, ST_ClosestPoint(r.geom, p.pt) as cp, ST_Distance(r.geom::geography, p.pt::geography) as d, p.pt
    from rang r, p where r.nr <= least(greatest(coalesce(max_per_typ, 25), 1), 100)
  )
  select jsonb_build_object(
    'summa', (select coalesce(jsonb_agg(to_jsonb(s) order by s.kategori, s.typ), '[]'::jsonb) from summa s),
    'lista', (select coalesce(jsonb_agg(jsonb_build_object(
                'kalla', l.kalla, 'kategori', l.kategori, 'typ', l.typ, 'ext_id', l.ext_id, 'namn', l.namn,
                'avstand_m', round(l.d::numeric),
                'riktning', coalesce(round(degrees(ST_Azimuth(l.pt::geography, l.cp::geography))::numeric), 0),
                'rangtext', l.egenskaper->>'rangtext', 'rang', (l.egenskaper->>'rang')::int, 'lista', (l.egenskaper->>'lista')::int,
                'nara_lat', ST_Y(l.cp), 'nara_lon', ST_X(l.cp), 'besokt', l.besokt) order by l.d), '[]'::jsonb)
              from lista l));
$$;
grant execute on function public.objekt_i_omrade(text, text, double precision, double precision, int, boolean) to anon, authenticated;
