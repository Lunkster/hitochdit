-- Topplistor 2026-10-07. Körd via Claude (execute_sql). Går att köra om.
-- Räknar bara VERIFIERADE besök (på plats, inom 100 m – se 20_sakerhet.sql), unika platser per period.
-- Ingen kan läsa andras besök eller profiler direkt: funktionerna är security definer och lämnar bara ut
-- placering, användarnamn och antal – aldrig e-post, user_id eller enskilda besök.

-- Opt-out (beslut 2026-10-05): alla är med från början och kan stänga av under Topplistor.
alter table public.profiler add column if not exists i_topplistor boolean not null default true;

-- Kategori för en källkod (samma indelning som i appen)
create or replace function public.kalla_kategori(k text) returns text
language sql immutable set search_path = '' as $$
  select case when k in ('NR', 'NP', 'NM') then 'natur'
              when k in ('KR', 'VA', 'BM', 'FL', 'KY', 'KO', 'FY') then 'kultur'
              when k in ('TA', 'SJ', 'OE', 'TO') then 'geo' end;
$$;

-- Topplista. p_tid: m (månad) | y (år) | a (totalt). p_niva: r (riket) | l (län, p_kod = länskod) | k (kommun, p_kod = kommunkod).
-- Svar: topp p_max + den som frågar (du = sant) med två platser runt sig. Datum räknas i svensk tid.
create or replace function public.topplista(p_tid text default 'y', p_ar int default null, p_manad int default null,
                                            p_kat text default 'alla', p_niva text default 'r', p_kod text default null,
                                            p_max int default 100)
returns table (plats int, namn text, antal int, du boolean, deltagare int)
language sql stable security definer set search_path = '' as $$
  with nu as (select (now() at time zone 'Europe/Stockholm')::date as d),
  per as (
    select case p_tid when 'm' then make_date(coalesce(p_ar, extract(year from nu.d)::int), coalesce(p_manad, extract(month from nu.d)::int), 1)
                      when 'y' then make_date(coalesce(p_ar, extract(year from nu.d)::int), 1, 1)
                      else date '1900-01-01' end as fran
    from nu),
  per2 as (select fran, case p_tid when 'm' then (fran + interval '1 month')::date when 'y' then (fran + interval '1 year')::date
                                   else date '3000-01-01' end as till from per),
  b as (
    select bb.user_id, count(distinct bb.scheme || ':' || bb.objekt_id)::int as antal
    from public.besok bb, per2
    where bb.verifierad
      and (bb.datum at time zone 'Europe/Stockholm')::date >= per2.fran
      and (bb.datum at time zone 'Europe/Stockholm')::date < per2.till
      and (coalesce(p_kat, 'alla') = 'alla' or public.kalla_kategori(bb.scheme) = p_kat)
      and (coalesce(p_niva, 'r') = 'r' or (p_niva = 'l' and bb.lanskod = p_kod) or (p_niva = 'k' and bb.kommunkod = p_kod))
    group by bb.user_id),
  m as (
    select b.antal, p.namn, b.user_id = (select auth.uid()) as du
    from b join public.profiler p on p.id = b.user_id
    where p.i_topplistor or b.user_id = (select auth.uid())),
  r as (select m.*, (rank() over (order by m.antal desc))::int as plats, (count(*) over ())::int as deltagare from m),
  jag as (select r.plats from r where r.du)
  select r.plats, coalesce(r.namn, 'Utan namn'), r.antal, r.du, r.deltagare
  from r
  where r.plats <= least(greatest(coalesce(p_max, 100), 1), 500)
     or r.du
     or abs(r.plats - coalesce((select jag.plats from jag), -100)) <= 2
  order by r.plats, r.du desc, lower(coalesce(r.namn, ''));
$$;
revoke execute on function public.topplista(text, int, int, text, text, text, int) from public, anon;
grant execute on function public.topplista(text, int, int, text, text, text, int) to authenticated;

-- Dina bästa placeringar: innevarande månad/år + totalt × alla kategorier × riket + dina 3 vanligaste län och kommuner
create or replace function public.mina_placeringar()
returns table (tid text, kat text, niva text, kod text, plats int, deltagare int)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare t text; k text; o record; r record; uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  for o in
    select 'r'::text as n, null::text as c
    union all (select 'l', bb.lanskod from public.besok bb where bb.user_id = uid and bb.verifierad and bb.lanskod is not null
               group by bb.lanskod order by count(*) desc limit 3)
    union all (select 'k', bb.kommunkod from public.besok bb where bb.user_id = uid and bb.verifierad and bb.kommunkod is not null
               group by bb.kommunkod order by count(*) desc limit 3)
  loop
    foreach t in array array['m', 'y', 'a'] loop
      foreach k in array array['alla', 'natur', 'kultur', 'geo'] loop
        select x.plats, x.deltagare into r from public.topplista(t, null, null, k, o.n, o.c, 1) x where x.du;
        if found then
          tid := t; kat := k; niva := o.n; kod := o.c; plats := r.plats; deltagare := r.deltagare;
          return next;
        end if;
      end loop;
    end loop;
  end loop;
end $$;
revoke execute on function public.mina_placeringar() from public, anon;
grant execute on function public.mina_placeringar() to authenticated;

-- Nu när topplistorna går via funktionerna: man kan bara läsa sin egen profil (tidigare alla inloggade).
-- (Användarnamnens unikhet kontrolleras av indexet profiler_namn_unik, inte genom att läsa andras.)
alter policy "profiler: alla inloggade kan läsa" on public.profiler using ((select auth.uid()) = id);
alter policy "profiler: alla inloggade kan läsa" on public.profiler rename to "profiler: läsa egen";
