-- Grupper och befogenheter 2026-10-08. Körd via Claude (execute_sql). Går att köra om.
-- Skrivet utan 'revoke all', 'drop' och update/delete utan where (se CLAUDE.md).
--
-- Befogenheter (beslut 2026-10-08, trappan i "Hit och Dit - Ekonomi"):
--   0 Ny        konto skapat           logga, topplistor, märken, gå med i grupper via inbjudan
--   1 Aktiv     25 verifierade platser bjuda in till grupper man är med i (dela gruppens kod/länk)
--   2 Erfaren  100 verifierade platser skapa egna grupper (högst 3)
--   3 Veteran  500 verifierade platser skapa fler grupper (högst 10)
-- Henrik kan låsa upp en nivå för en användare i tabellen befogenheter (Table Editor) – t.ex. under testet.
-- Ingen kan läsa grupptabellerna direkt; allt går via funktionerna nedan (security definer).
-- Den som går med i en grupp syns i gruppens topplista även om hen är dold i de allmänna topplistorna.

create table if not exists public.befogenheter (
  user_id uuid primary key references auth.users on delete cascade,
  niva int not null check (niva between 0 and 3),
  notering text,
  satt timestamptz not null default now());

create table if not exists public.grupper (
  id uuid primary key default gen_random_uuid(),
  namn text not null check (char_length(btrim(namn)) between 3 and 40),
  kod text not null unique,
  skapad timestamptz not null default now(),
  skapad_av uuid references auth.users on delete set null);
create unique index if not exists grupper_namn_unik on public.grupper (lower(btrim(namn)));

create table if not exists public.grupp_medlemmar (
  grupp_id uuid not null references public.grupper on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  roll text not null default 'medlem' check (roll in ('agare', 'medlem')),
  gick_med timestamptz not null default now(),
  primary key (grupp_id, user_id));
create index if not exists grupp_medlemmar_user on public.grupp_medlemmar (user_id);

alter table public.befogenheter enable row level security;
alter table public.grupper enable row level security;
alter table public.grupp_medlemmar enable row level security;
revoke select, insert, update, delete, truncate, references, trigger on public.befogenheter, public.grupper, public.grupp_medlemmar from anon, authenticated;

-- Ägaren försvinner (lämnar eller raderar kontot): den som varit med längst tar över. Tom grupp raderas.
create or replace function public.grupp_efter_utgang() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.grupp_medlemmar where grupp_id = old.grupp_id) then
    delete from public.grupper where id = old.grupp_id;
  elsif old.roll = 'agare' and not exists (select 1 from public.grupp_medlemmar where grupp_id = old.grupp_id and roll = 'agare') then
    update public.grupp_medlemmar set roll = 'agare'
    where grupp_id = old.grupp_id
      and user_id = (select user_id from public.grupp_medlemmar where grupp_id = old.grupp_id order by gick_med, user_id limit 1);
  end if;
  return null;
end $$;
revoke execute on function public.grupp_efter_utgang() from public, anon, authenticated;
create or replace trigger grupp_efter_utgang after delete on public.grupp_medlemmar
  for each row execute function public.grupp_efter_utgang();

-- Inbjudningskod: 8 tecken utan förväxlingsbara tecken (0/O, 1/I/L), visas som XXXX-XXXX
create or replace function public.grupp_slumpkod() returns text
language plpgsql volatile set search_path = '' as $$
declare a text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; b bytea := uuid_send(gen_random_uuid()); k text := ''; i int;
begin
  for i in 0..7 loop k := k || substr(a, 1 + get_byte(b, i) % length(a), 1); end loop;
  return k;
end $$;
revoke execute on function public.grupp_slumpkod() from public, anon, authenticated;

create or replace function public.grupp_kodnorm(p text) returns text
language sql immutable set search_path = '' as $$ select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')) $$;

-- Befogenhetsnivå: antal olika verifierade platser (all tid), eller upplåst nivå om den är högre
create or replace function public.befogenhet(uid uuid)
returns table (niva int, verifierade int, upplast int)
language sql stable security definer set search_path = '' as $$
  with v as (select count(distinct b.scheme || ':' || b.objekt_id)::int as n from public.besok b where b.user_id = uid and b.verifierad),
       u as (select coalesce((select f.niva from public.befogenheter f where f.user_id = uid), 0) as n)
  select greatest(case when v.n >= 500 then 3 when v.n >= 100 then 2 when v.n >= 25 then 1 else 0 end, u.n), v.n, u.n from v, u;
$$;
revoke execute on function public.befogenhet(uuid) from public, anon, authenticated;

create or replace function public.mina_befogenheter()
returns table (niva int, verifierade int, upplast int, egna int, max_egna int)
language sql stable security definer set search_path = '' as $$
  select b.niva, b.verifierade, b.upplast,
         (select count(*)::int from public.grupp_medlemmar m where m.user_id = auth.uid() and m.roll = 'agare'),
         case b.niva when 3 then 10 when 2 then 3 else 0 end
  from public.befogenhet(auth.uid()) b where auth.uid() is not null;
$$;

create or replace function public.mina_grupper()
returns table (id uuid, namn text, roll text, medlemmar int, kod text, gick_med timestamptz)
language sql stable security definer set search_path = '' as $$
  select g.id, g.namn, m.roll, (select count(*)::int from public.grupp_medlemmar x where x.grupp_id = g.id),
         case when m.roll = 'agare' or (select b.niva from public.befogenhet(auth.uid()) b) >= 1 then g.kod end, m.gick_med
  from public.grupp_medlemmar m join public.grupper g on g.id = m.grupp_id
  where m.user_id = auth.uid()
  order by lower(g.namn);
$$;

create or replace function public.grupp_skapa(p_namn text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := auth.uid(); n int; egna int; gid uuid; k text;
begin
  if uid is null then raise exception 'Inte inloggad'; end if;
  select b.niva into n from public.befogenhet(uid) b;
  select count(*) into egna from public.grupp_medlemmar where user_id = uid and roll = 'agare';
  if n < 2 then raise exception 'Du kan skapa grupper när du har 100 verifierade platser'; end if;
  if egna >= (case n when 3 then 10 else 3 end) then raise exception 'Du har redan så många egna grupper som din nivå tillåter'; end if;
  if char_length(btrim(coalesce(p_namn, ''))) not between 3 and 40 then raise exception 'Gruppens namn ska vara 3–40 tecken'; end if;
  if exists (select 1 from public.grupper where lower(btrim(namn)) = lower(btrim(p_namn))) then raise exception 'Det finns redan en grupp med det namnet'; end if;
  loop k := public.grupp_slumpkod(); exit when not exists (select 1 from public.grupper where kod = k); end loop;
  insert into public.grupper (namn, kod, skapad_av) values (btrim(p_namn), k, uid) returning id into gid;
  insert into public.grupp_medlemmar (grupp_id, user_id, roll) values (gid, uid, 'agare');
  return gid;
end $$;

-- Vad en inbjudningskod leder till (för bekräftelsen "Gå med i …?")
create or replace function public.grupp_info(p_kod text)
returns table (namn text, medlemmar int, med boolean, fullsatt boolean)
language sql stable security definer set search_path = '' as $$
  select g.namn, c.n, exists (select 1 from public.grupp_medlemmar m where m.grupp_id = g.id and m.user_id = auth.uid()), c.n >= 50
  from public.grupper g, lateral (select count(*)::int as n from public.grupp_medlemmar x where x.grupp_id = g.id) c
  where auth.uid() is not null and g.kod = public.grupp_kodnorm(p_kod);
$$;

create or replace function public.grupp_ga_med(p_kod text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := auth.uid(); gid uuid;
begin
  if uid is null then raise exception 'Inte inloggad'; end if;
  select id into gid from public.grupper where kod = public.grupp_kodnorm(p_kod);
  if gid is null then raise exception 'Hittar ingen grupp med den koden'; end if;
  if exists (select 1 from public.grupp_medlemmar where grupp_id = gid and user_id = uid) then return gid; end if;
  if (select count(*) from public.grupp_medlemmar where grupp_id = gid) >= 50 then raise exception 'Gruppen är full (50 medlemmar)'; end if;
  if (select count(*) from public.grupp_medlemmar where user_id = uid) >= 20 then raise exception 'Du kan vara med i högst 20 grupper'; end if;
  insert into public.grupp_medlemmar (grupp_id, user_id) values (gid, uid);
  return gid;
end $$;

create or replace function public.grupp_lamna(p_id uuid) returns void
language sql volatile security definer set search_path = '' as $$
  delete from public.grupp_medlemmar where grupp_id = p_id and user_id = auth.uid();
$$;

create or replace function public.grupp_ny_kod(p_id uuid) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare k text;
begin
  if not exists (select 1 from public.grupp_medlemmar where grupp_id = p_id and user_id = auth.uid() and roll = 'agare') then
    raise exception 'Bara gruppens ägare kan byta kod'; end if;
  loop k := public.grupp_slumpkod(); exit when not exists (select 1 from public.grupper where kod = k); end loop;
  update public.grupper set kod = k where id = p_id;
  return k;
end $$;

create or replace function public.grupp_radera(p_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.grupp_medlemmar where grupp_id = p_id and user_id = auth.uid() and roll = 'agare') then
    raise exception 'Bara gruppens ägare kan ta bort gruppen'; end if;
  delete from public.grupper where id = p_id;
end $$;

revoke execute on function public.mina_befogenheter(), public.mina_grupper(), public.grupp_skapa(text), public.grupp_info(text),
  public.grupp_ga_med(text), public.grupp_lamna(uuid), public.grupp_ny_kod(uuid), public.grupp_radera(uuid), public.grupp_kodnorm(text) from public, anon;
grant execute on function public.mina_befogenheter(), public.mina_grupper(), public.grupp_skapa(text), public.grupp_info(text),
  public.grupp_ga_med(text), public.grupp_lamna(uuid), public.grupp_ny_kod(uuid), public.grupp_radera(uuid), public.grupp_kodnorm(text) to authenticated;

-- Topplistan får nivån g (grupp, p_kod = gruppens id): bara gruppens medlemmar, och bara för den som själv är med.
-- I gruppens lista syns alla medlemmar (att gå med = att synas för gruppen), även de som är dolda i de allmänna listorna.
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
  grp as (select gm.user_id from public.grupp_medlemmar gm
          where p_niva = 'g' and gm.grupp_id::text = p_kod
            and exists (select 1 from public.grupp_medlemmar j where j.grupp_id = gm.grupp_id and j.user_id = (select auth.uid()))),
  b as (
    select bb.user_id, count(distinct bb.scheme || ':' || bb.objekt_id)::int as antal
    from public.besok bb, per2
    where bb.verifierad
      and (bb.datum at time zone 'Europe/Stockholm')::date >= per2.fran
      and (bb.datum at time zone 'Europe/Stockholm')::date < per2.till
      and (coalesce(p_kat, 'alla') = 'alla' or public.kalla_kategori(bb.scheme) = p_kat)
      and (coalesce(p_niva, 'r') = 'r' or (p_niva = 'l' and bb.lanskod = p_kod) or (p_niva = 'k' and bb.kommunkod = p_kod)
           or (p_niva = 'g' and bb.user_id in (select grp.user_id from grp)))
    group by bb.user_id),
  m as (
    select b.antal, p.namn, b.user_id = (select auth.uid()) as du
    from b join public.profiler p on p.id = b.user_id
    where p.i_topplistor or b.user_id = (select auth.uid()) or p_niva = 'g'),
  r as (select m.*, (rank() over (order by m.antal desc))::int as plats, (count(*) over ())::int as deltagare from m),
  jag as (select r.plats from r where r.du)
  select r.plats, coalesce(r.namn, 'Utan namn'), r.antal, r.du, r.deltagare
  from r
  where r.plats <= least(greatest(coalesce(p_max, 100), 1), 500)
     or r.du
     or abs(r.plats - coalesce((select jag.plats from jag), -100)) <= 2
  order by r.plats, r.du desc, lower(coalesce(r.namn, ''));
$$;

-- Dina bästa placeringar: nu även i dina grupper
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
    union all (select 'g', gm.grupp_id::text from public.grupp_medlemmar gm where gm.user_id = uid)
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
