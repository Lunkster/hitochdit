-- Snabbare hämtning av ytor (klick i "I närheten", träfflistan och besökta platser i kartan).
-- objekt_geom sökte på kalla || ':' || ext_id – det kan inte använda indexet på (kalla, ext_id), så alla ~330 000
-- objekt gicks igenom varje gång (och frågan avbröts ibland av Supabases tidsgräns). Nu delas nyckeln upp och
-- indexet används. ext_id kan själv innehålla ':' (t.ex. fornlämningen L1969:3430), därför delas bara vid första ':'.
-- Kör i SQL Editor. Går att köra om.

drop function if exists public.objekt_geom(text[]);
create function public.objekt_geom(nycklar text[])
returns table (kalla text, ext_id text, typ text, namn text, url text, geojson json)
language sql stable set search_path = public, extensions as $$
  with n as (
    select split_part(k, ':', 1) as kalla, substr(k, position(':' in k) + 1) as ext_id
    from unnest(nycklar) k where position(':' in k) > 0
    limit 500
  )
  select o.kalla, o.ext_id, o.typ, o.namn, coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         ST_AsGeoJSON(ST_SimplifyPreserveTopology(o.geom, 0.00003), 6)::json
  from n join public.objekt o on o.kalla = n.kalla and o.ext_id = n.ext_id;
$$;
grant execute on function public.objekt_geom(text[]) to anon, authenticated;

-- I närheten: även koordinaten för närmaste punkt på objektet, så att kartan kan zooma direkt
drop function if exists public.objekt_nara(double precision, double precision, double precision, int);
create function public.objekt_nara(lat double precision, lon double precision,
                                   radie_m double precision default 10000, max_per_typ int default 12)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision,
               riktning double precision, rangtext text, rang int, lista int, nara_lat double precision, nara_lon double precision)
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
         i.egenskaper->>'rangtext', (i.egenskaper->>'rang')::int, (i.egenskaper->>'lista')::int,
         ST_Y(i.cp), ST_X(i.cp)
  from inom i
  where i.nr <= greatest(coalesce(max_per_typ, 12), 1)
  order by i.d
  limit 150;
$$;
grant execute on function public.objekt_nara(double precision, double precision, double precision, int) to anon, authenticated;
