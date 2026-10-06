-- "I närheten": objekt runt en position med avstånd (till närmaste kant/punkt) och riktning (grader, 0 = norr).
-- Som mest max_per_typ per källa, så att t.ex. fornlämningar inte tränger undan allt annat. Objekt man står i
-- (närmare än 30 m) visas som träff i appen och tas inte med här. Kör i SQL Editor. Går att köra om.
create or replace function public.objekt_nara(lat double precision, lon double precision,
                                              radie_m double precision default 10000, max_per_typ int default 12)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision,
               riktning double precision, rangtext text, rang int, lista int)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt,
                    least(greatest(coalesce(radie_m, 10000), 100), 30000) as r),
  kand as (
    select o.kalla, o.kategori, o.typ, o.ext_id, o.namn, o.egenskaper,
           ST_Distance(o.geom::geography, p.pt::geography) as d,
           ST_ClosestPoint(o.geom, p.pt) as cp, p.pt
    from public.objekt o, p
    where o.geom && ST_Expand(p.pt, p.r / (111320 * cos(radians(lat))), p.r / 110574)
      and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  ),
  inom as (
    select k.*, row_number() over (partition by k.kalla order by k.d) as nr
    from kand k, p where k.d <= p.r and k.d >= 30
  )
  select i.kalla, i.kategori, i.typ, i.ext_id, i.namn, round(i.d::numeric)::double precision,
         round(degrees(ST_Azimuth(i.pt::geography, i.cp::geography))::numeric)::double precision,
         i.egenskaper->>'rangtext', (i.egenskaper->>'rang')::int, (i.egenskaper->>'lista')::int
  from inom i
  where i.nr <= greatest(coalesce(max_per_typ, 12), 1)
  order by i.d
  limit 150;
$$;
grant execute on function public.objekt_nara(double precision, double precision, double precision, int) to anon, authenticated;
