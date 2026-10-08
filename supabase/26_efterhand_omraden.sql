-- Områden för efterhandsbesök 2026-10-08 (beslut Henrik: "mellanvägen"). Körd via Claude. Går att köra om.
-- Besök PÅ PLATS: som förut – kommun, socken och landskap där man stod (närmaste inom 25 km, län från kommunen).
-- Besök I EFTERHAND: positionen säger inget (man kan klicka var som helst i t.ex. Vättern) och en mittpunkt blir fel för
-- stora objekt. Därför får efterhandsbesöket ett område bara om objektet ligger helt inom det: kommun, län, socken och
-- landskap prövas var för sig. Spänner objektet över flera (Vättern: 8 kommuner, 4 län) blir fältet tomt.
-- "Helt inom" = minst 98 % av objektets yta (längd för linjer, punkter för multipunkter) ligger i samma område – räknat på
-- den del som ligger i något område, så att gränser som inte är exakt samma i olika datakällor och delar ute i havet
-- inte fäller avgörandet. Enstaka punkter (kyrkor, fyrar, toppar, naturminnen) får närmaste område inom 25 km, som på plats.

create or replace function public.omrade_helt_inom(og extensions.geometry, p_typ text) returns text
language plpgsql stable set search_path = public, extensions as $$
declare dim int; k text; andel float8;
begin
  if og is null then return null; end if;
  dim := ST_Dimension(og);
  if GeometryType(og) = 'GEOMETRYCOLLECTION' then og := ST_CollectionExtract(og, dim + 1); end if;
  if dim = 0 and ST_NumGeometries(og) = 1 then
    select i.kod into k from public.indelning i
    where i.typ = p_typ and i.geom && ST_Expand(og, 0.5) and ST_DWithin(i.geom::geography, og::geography, 25000)
    order by ST_Distance(i.geom::geography, og::geography) limit 1;
    return k;
  end if;
  select x.kod, x.del / nullif(sum(x.del) over (), 0) into k, andel
  from (select i.kod, case dim when 2 then ST_Area(ST_Intersection(i.geom, og))
                               when 1 then ST_Length(ST_Intersection(i.geom, og))
                               else ST_NumGeometries(ST_Intersection(i.geom, og)) end as del
        from public.indelning i
        where i.typ = p_typ and i.geom && og and ST_Intersects(i.geom, og)) x
  order by x.del desc limit 1;
  return case when andel >= 0.98 then k end;
end $$;
revoke execute on function public.omrade_helt_inom(extensions.geometry, text) from public, anon;
-- Triggern körs som den inloggade (inte security definer) och behöver anropa funktionen. Den läser bara kartindelningen.
grant execute on function public.omrade_helt_inom(extensions.geometry, text) to authenticated;

create or replace function public.besok_satt_indelning() returns trigger
language plpgsql set search_path = public, extensions as $$
declare pt geometry; og geometry;
begin
  if new.pa_plats is not false and new.lat is not null and new.lon is not null then
    pt := ST_SetSRID(ST_MakePoint(new.lon, new.lat), 4326);
    select i.kod, i.lanskod into new.kommunkod, new.lanskod
    from public.indelning i
    where i.typ = 'kommun' and i.geom && ST_Expand(pt, 0.5) and ST_DWithin(i.geom::geography, pt::geography, 25000)
    order by ST_Distance(i.geom::geography, pt::geography) limit 1;
    select i.kod into new.sockenkod
    from public.indelning i
    where i.typ = 'socken' and i.geom && ST_Expand(pt, 0.5) and ST_DWithin(i.geom::geography, pt::geography, 25000)
    order by ST_Distance(i.geom::geography, pt::geography) limit 1;
    select i.kod into new.landskap
    from public.indelning i
    where i.typ = 'landskap' and i.geom && ST_Expand(pt, 0.5) and ST_DWithin(i.geom::geography, pt::geography, 25000)
    order by ST_Distance(i.geom::geography, pt::geography) limit 1;
  else
    select o.geom into og from public.objekt o where o.kalla = new.scheme and o.ext_id = new.objekt_id limit 1;
    if og is null and new.nvrid is not null then
      select o.geom into og from public.objekt o where o.kalla in ('NR', 'NP', 'KR') and o.ext_id = new.nvrid limit 1;
    end if;
    new.kommunkod := public.omrade_helt_inom(og, 'kommun');
    new.lanskod   := public.omrade_helt_inom(og, 'lan');
    new.sockenkod := public.omrade_helt_inom(og, 'socken');
    new.landskap  := public.omrade_helt_inom(og, 'landskap');
  end if;
  return new;
end $$;
revoke execute on function public.besok_satt_indelning() from public, anon, authenticated;
create or replace trigger besok_indelning before insert or update of lat, lon, objekt_id, scheme, nvrid, pa_plats on public.besok
  for each row execute function public.besok_satt_indelning();

-- Befintliga efterhandsbesök räknas om (0 st när filen skrevs)
update public.besok set pa_plats = pa_plats where not pa_plats;
