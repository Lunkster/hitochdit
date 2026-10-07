-- Märken (loggmärken) och medaljer 2026-10-08. Körd via Claude (execute_sql). Går att köra om.
-- Regler: se märkesmockupen och Naturapp.md (tågordningen, punkt 9).

-- ============ Loggmärken ============
-- Märkesgrupp för ett objekt: källkoden, men kyrkor (RAÄ KY + OSM KO) ihop och fornlämningar per lämningstyp.
create or replace function public.marke_grupp(k text, e jsonb) returns text
language sql immutable set search_path = '' as $$
  select case when k = 'FL' then 'FL:' || case e->>'lamningstyp' when 'Stensättning' then 'sten' when 'Boplats' then 'bopl'
                                          when 'Hällristning' then 'hall' when 'Runristning' then 'rune' when 'Fornborg' then 'borg' else 'ovr' end
              when k in ('KY', 'KO') then 'KY' else k end;
$$;

-- Totalt antal per märkesgrupp. Räknas i förväg (tar ca 10 s) – kör marke_totaler_uppdatera() efter laddning av geodata.
create table if not exists public.marke_totaler (
  grupp      text primary key,
  totalt     int not null,
  uppdaterad timestamptz not null default now()
);
alter table public.marke_totaler enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'marke_totaler' and policyname = 'marke_totaler: alla kan läsa') then
    create policy "marke_totaler: alla kan läsa" on public.marke_totaler for select to anon, authenticated using (true);
  end if;
end $$;
grant select on public.marke_totaler to anon, authenticated;

create or replace function public.marke_totaler_uppdatera() returns int
language sql security definer set search_path = '' as $$
  with t as (
    select public.marke_grupp(o.kalla, o.egenskaper) as g, count(*)::int as n
    from public.objekt o where not (coalesce(o.egenskaper, '{}'::jsonb) ? 'utgatt') group by 1
    union all
    select case i.typ when 'lan' then 'LN' when 'kommun' then 'KN' when 'landskap' then 'LS' when 'socken' then 'SO' end, count(*)::int
    from public.indelning i group by i.typ),
  u as (insert into public.marke_totaler (grupp, totalt, uppdaterad)
        select g, n, now() from t where g is not null
        on conflict (grupp) do update set totalt = excluded.totalt, uppdaterad = now()
        returning 1)
  select count(*)::int from u;
$$;
revoke execute on function public.marke_totaler_uppdatera() from public, anon, authenticated;

-- Mina märken: antal olika platser per märkesgrupp, bara besök på plats (inte efterhand), all tid.
-- Körs som anroparen – RLS ger bara de egna besöken. Utgångna objekt räknas (man var där).
create or replace function public.mina_marken() returns table (grupp text, antal int)
language sql stable set search_path = '' as $$
  with b as (select * from public.besok where user_id = (select auth.uid()) and pa_plats),
  o as (
    select distinct x.kalla, x.ext_id, x.egenskaper
    from b cross join lateral (
      (select o.kalla, o.ext_id, o.egenskaper from public.objekt o where o.kalla = b.scheme and o.ext_id = b.objekt_id)
      union
      (select o.kalla, o.ext_id, o.egenskaper from public.objekt o
       where b.nvrid is not null and o.kalla in ('NR', 'NP', 'KR', 'NM') and o.ext_id = b.nvrid)) x)
  select public.marke_grupp(o.kalla, o.egenskaper), count(*)::int from o group by 1
  union all select 'LN', count(distinct b.lanskod)::int from b where b.lanskod is not null
  union all select 'KN', count(distinct b.kommunkod)::int from b where b.kommunkod is not null
  union all select 'LS', count(distinct b.landskap)::int from b where b.landskap is not null
  union all select 'SO', count(distinct b.sockenkod)::int from b where b.sockenkod is not null;
$$;
revoke execute on function public.mina_marken() from public, anon;
grant execute on function public.mina_marken() to authenticated;

-- ============ Medaljer ============
-- Guld/silver/brons för topp 3 i topplistan (hela Sverige) per månad och år, i fyra cuper: alla, natur, kultur, geo.
-- Beslut 2026-10-08: samma räkning som topplistan (verifierade unika platser), delas ut när perioden är slut,
-- delad placering = samma valör (rank 1, 1, 3), minst 3 deltagare, dolda i topplistor är inte med, vunnen medalj ligger kvar.
create table if not exists public.medaljer (
  user_id   uuid not null references auth.users on delete cascade,
  cup       text not null check (cup in ('alla', 'natur', 'kultur', 'geo')),
  tid       text not null check (tid in ('m', 'y')),
  period    date not null,             -- första dagen i månaden/året
  plats     int not null check (plats between 1 and 3),
  antal     int not null,
  deltagare int not null,
  utdelad   timestamptz not null default now(),
  primary key (user_id, cup, tid, period)
);
alter table public.medaljer enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'medaljer' and policyname = 'medaljer: läsa egna') then
    create policy "medaljer: läsa egna" on public.medaljer for select to authenticated using ((select auth.uid()) = user_id);
  end if;
end $$;
grant select on public.medaljer to authenticated;

-- Vilka perioder som är avgjorda (bara för funktionerna nedan – ingen åtkomst från appen)
create table if not exists public.medalj_perioder (
  tid    text not null,
  period date not null,
  avgjord timestamptz not null default now(),
  primary key (tid, period)
);
alter table public.medalj_perioder enable row level security;

create or replace function public.medaljer_dela_ut(p_tid text, p_fran date, p_till date) returns int
language plpgsql security definer set search_path = '' as $$
declare k text; c int; n int := 0;
begin
  foreach k in array array['alla', 'natur', 'kultur', 'geo'] loop
    with b as (
      select bb.user_id, count(distinct bb.scheme || ':' || bb.objekt_id)::int as antal
      from public.besok bb join public.profiler pr on pr.id = bb.user_id
      where bb.verifierad and pr.i_topplistor
        and (bb.datum at time zone 'Europe/Stockholm')::date >= p_fran
        and (bb.datum at time zone 'Europe/Stockholm')::date < p_till
        and (k = 'alla' or public.kalla_kategori(bb.scheme) = k)
      group by bb.user_id),
    r as (select b.*, (rank() over (order by b.antal desc))::int as plats, (count(*) over ())::int as deltagare from b),
    ins as (insert into public.medaljer (user_id, cup, tid, period, plats, antal, deltagare)
            select r.user_id, k, p_tid, p_fran, r.plats, r.antal, r.deltagare from r where r.plats <= 3 and r.deltagare >= 3
            on conflict do nothing returning 1)
    select count(*) into c from ins;
    n := n + c;
  end loop;
  return n;
end $$;
revoke execute on function public.medaljer_dela_ut(text, date, date) from public, anon, authenticated;

-- Avgör alla avslutade månader (från september 2026) och år som inte är avgjorda än. Körs när någon öppnar märkena.
create or replace function public.medaljer_ikapp() returns int
language plpgsql security definer set search_path = '' as $$
declare idag date := (now() at time zone 'Europe/Stockholm')::date; p date; n int := 0;
begin
  perform pg_advisory_xact_lock(47110001);
  p := date '2026-09-01';
  while p < date_trunc('month', idag)::date loop
    if not exists (select 1 from public.medalj_perioder mp where mp.tid = 'm' and mp.period = p) then
      n := n + public.medaljer_dela_ut('m', p, (p + interval '1 month')::date);
      insert into public.medalj_perioder (tid, period) values ('m', p);
    end if;
    p := (p + interval '1 month')::date;
  end loop;
  p := date '2026-01-01';
  while p < date_trunc('year', idag)::date loop
    if not exists (select 1 from public.medalj_perioder mp where mp.tid = 'y' and mp.period = p) then
      n := n + public.medaljer_dela_ut('y', p, (p + interval '1 year')::date);
      insert into public.medalj_perioder (tid, period) values ('y', p);
    end if;
    p := (p + interval '1 year')::date;
  end loop;
  return n;
end $$;
revoke execute on function public.medaljer_ikapp() from public, anon, authenticated;

-- Mina medaljer (avgör först eventuella nya perioder)
create or replace function public.mina_medaljer()
returns table (cup text, tid text, period date, plats int, antal int, deltagare int)
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if auth.uid() is null then return; end if;
  perform public.medaljer_ikapp();
  return query select m.cup, m.tid, m.period, m.plats, m.antal, m.deltagare
               from public.medaljer m where m.user_id = auth.uid() order by m.period desc, m.plats, m.cup;
end $$;
revoke execute on function public.mina_medaljer() from public, anon;
grant execute on function public.mina_medaljer() to authenticated;

-- Räkna totalerna första gången
select public.marke_totaler_uppdatera();
