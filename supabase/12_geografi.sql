-- Geografi (300-listorna: tätorter TA, sjöar SJ) + gemensamt mönster för uppdatering av objekt.
-- Kör i SQL Editor INNAN tools/ladda_tatorter.sh och tools/ladda_sjoar.sh. Går att köra om.
--
-- Uppdateringsmönster (alla laddskript):
--   1. Ny data upsertas på (kalla, ext_id) – egenskaper ersätts, så ett objekt som kommer tillbaka blir aktivt igen.
--   2. Objekt som inte längre finns i källan (eller faller ur en 300-lista) rensas med public.objekt_stada():
--      - har ingen besökt det → tas bort
--      - har någon besökt det → ligger kvar med egenskaper.utgatt = datum, så att besöket behåller sin yta och sitt namn.
--        Utgångna objekt ger inga nya träffar (objekt_vid, objekt_i_ruta, objekt_ytor_i_ruta).

create index if not exists besok_objekt on public.besok (scheme, objekt_id);

-- Har någon besökt objektet? (NV-objekt kan också vara kopplade via nvrid)
create or replace function public.objekt_besokt(p_kalla text, p_ext_id text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from public.besok b where b.scheme = p_kalla and b.objekt_id = p_ext_id)
      or (p_kalla in ('NR', 'NP', 'KR') and exists (select 1 from public.besok b where b.nvrid = p_ext_id));
$$;

-- Rensa objekt i p_kallor vars 'KALLA:ext_id' inte finns i p_aktuella. Körs bara av laddskripten (som postgres).
create or replace function public.objekt_stada(p_kallor text[], p_aktuella text[])
returns table (borttagna bigint, utgangna bigint)
language plpgsql set search_path = public as $$
declare d bigint; u bigint;
begin
  create temp table _aktuella on commit drop as select unnest(p_aktuella) as nyckel;
  create index on _aktuella (nyckel);
  with x as (
    update public.objekt o set egenskaper = coalesce(o.egenskaper, '{}'::jsonb) || jsonb_build_object('utgatt', current_date), uppdaterad = now()
    where o.kalla = any(p_kallor)
      and not exists (select 1 from _aktuella a where a.nyckel = o.kalla || ':' || o.ext_id)
      and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
      and public.objekt_besokt(o.kalla, o.ext_id)
    returning 1)
  select count(*) into u from x;
  with x as (
    delete from public.objekt o
    where o.kalla = any(p_kallor)
      and not exists (select 1 from _aktuella a where a.nyckel = o.kalla || ':' || o.ext_id)
      and not public.objekt_besokt(o.kalla, o.ext_id)
    returning 1)
  select count(*) into d from x;
  drop table _aktuella;
  return query select d, u;
end $$;
-- Ska inte gå att anropa från appen
revoke execute on function public.objekt_stada(text[], text[]) from public, anon, authenticated;
revoke execute on function public.objekt_besokt(text, text) from public, anon, authenticated;

-- Position -> objekt. Nytt: rang/lista (300-listorna), utgångna objekt hoppas över, sjöar räknas inom minst 50 m från stranden.
drop function if exists public.objekt_vid(double precision, double precision, double precision, text[]);
create function public.objekt_vid(lat double precision, lon double precision,
                                  radie_m double precision default 25, kallor text[] default null)
returns table (kalla text, kategori text, typ text, ext_id text, namn text, avstand_m double precision, url text, rang int, lista int)
language sql stable set search_path = public, extensions as $$
  with p as (select ST_SetSRID(ST_MakePoint(lon, lat), 4326) as pt,
                    greatest(coalesce(radie_m, 0), 0) as r)
  select o.kalla, o.kategori, o.typ, o.ext_id, o.namn,
         round(ST_Distance(o.geom::geography, p.pt::geography)::numeric, 1)::double precision,
         coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         (o.egenskaper->>'rang')::int, (o.egenskaper->>'lista')::int
  from public.objekt o, p
  where o.geom && ST_Expand(p.pt, greatest(p.r, 50) / 30000.0)
    and ST_DWithin(o.geom::geography, p.pt::geography, case when o.kalla = 'SJ' then greatest(p.r, 50) else p.r end)
    and (kallor is null or o.kalla = any(kallor))
    and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  order by 6, o.namn
  limit 50;
$$;
grant execute on function public.objekt_vid(double precision, double precision, double precision, text[]) to anon, authenticated;

-- Symboler (kyrkor, fyrar): utgångna hoppas över
create or replace function public.objekt_i_ruta(kallor text[], vast double precision, syd double precision,
                                                ost double precision, norr double precision, max_antal int default 1500)
returns table (kalla text, typ text, ext_id text, namn text, url text, lat double precision, lon double precision)
language sql stable set search_path = public, extensions as $$
  select o.kalla, o.typ, o.ext_id, o.namn, coalesce(o.egenskaper->>'url', o.egenskaper->>'unesco'),
         ST_Y(ST_PointOnSurface(o.geom)), ST_X(ST_PointOnSurface(o.geom))
  from public.objekt o
  where o.kalla = any(kallor)
    and o.geom && ST_MakeEnvelope(vast, syd, ost, norr, 4326)
    and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  limit least(coalesce(max_antal, 1500), 5000);
$$;
grant execute on function public.objekt_i_ruta(text[], double precision, double precision, double precision, double precision, int) to anon, authenticated;

-- Ytor inom kartutsnittet, förenklade efter zoomnivå och klippta mot utsnittet – för kartskikten Tätorter och Sjöar.
create or replace function public.objekt_ytor_i_ruta(kallor text[], vast double precision, syd double precision,
                                                     ost double precision, norr double precision, tolerans double precision default 0.0005)
returns table (kalla text, ext_id text, namn text, rang int, geojson json)
language sql stable set search_path = public, extensions as $$
  with r as (select ST_MakeEnvelope(vast, syd, ost, norr, 4326) as box,
                    greatest(coalesce(tolerans, 0.0005), 0.00003) as tol)
  select o.kalla, o.ext_id, o.namn, (o.egenskaper->>'rang')::int,
         ST_AsGeoJSON(ST_SimplifyPreserveTopology(ST_ClipByBox2D(o.geom, ST_Expand(r.box, r.tol * 20)), r.tol), 5)::json
  from public.objekt o, r
  where o.kalla = any(kallor) and o.geom && r.box
    and not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt')
  limit 600;
$$;
grant execute on function public.objekt_ytor_i_ruta(text[], double precision, double precision, double precision, double precision, double precision) to anon, authenticated;
