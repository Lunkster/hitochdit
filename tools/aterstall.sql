-- Används av tools/aterstall.sh (körs inom en transaktion som skriptet avslutar med commit eller rollback).
-- Förutsätter tillfälliga tabeller s_konton, s_profiler, s_besok, s_meddelanden och ev. s_medaljer, s_grupper,
-- s_grupp_medlemmar, s_befogenheter (text-kolumner) från kopian
-- (kopior från före 2026-10-08 saknar medaljer.csv – då hoppas medaljerna över)
-- och inställningen aterstall.epost ('' = alla användare).

-- Gammalt användar-id -> nuvarande konto, via e-post
create temp table anvkarta as
select k.id::uuid as gammal, u.id as ny, k.email as epost
from s_konton k join auth.users u on lower(u.email) = lower(k.email);

\echo '=== Konton i kopian som saknas nu – de måste logga in i appen först, deras data hoppas över ==='
select k.email as epost from s_konton k
where not exists (select 1 from anvkarta a where a.gammal = k.id::uuid)
  and (current_setting('aterstall.epost') = '' or lower(k.email) = lower(current_setting('aterstall.epost')));

-- Inga ntfy-aviseringar för återställda meddelanden
alter table public.meddelanden disable trigger user;

-- Profiler: användarnamnet läggs tillbaka om kontot saknar namn (ett nytt konto får en tom profil vid första
-- inloggningen) och ingen annan har tagit namnet.
do $$
declare n bigint; tot bigint; v_epost text := current_setting('aterstall.epost');
begin
  select count(*) into tot from s_profiler;
  insert into public.profiler (id, namn, skapad)
  select m.ny, nullif(s.namn, ''), coalesce(nullif(s.skapad, '')::timestamptz, now())
  from s_profiler s join anvkarta m on m.gammal = s.id::uuid
  where (v_epost = '' or lower(m.epost) = lower(v_epost))
    and not exists (select 1 from public.profiler p where p.id <> m.ny and lower(trim(p.namn)) = lower(trim(s.namn)))
  on conflict (id) do update set namn = excluded.namn
    where public.profiler.namn is null and excluded.namn is not null;
  get diagnostics n = row_count;
  raise notice 'profiler: % i kopian, % återställda', tot, n;
end $$;

-- Besök och meddelanden får nya id:n (krockar aldrig med rader som skapats efter olyckan). En rad som redan finns –
-- samma användare, plats och tidpunkt (besök) resp. samma tid och text (meddelande) – läggs inte in igen.
do $$
declare
  t text; kol text; uttr text; villkor text; finns text; n bigint; tot bigint;
  v_epost text := current_setting('aterstall.epost');
begin
  foreach t in array array['besok', 'meddelanden'] loop
    if to_regclass('pg_temp.s_' || t) is null then continue; end if;
    -- Kolumner som finns både i kopian och i tabellen (utom id); user_id byts mot nuvarande konto
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum),
           string_agg(case when a.attname = 'user_id' then 'm.ny'
                           else format('nullif(s.%I, %L)::%s', a.attname, '', format_type(a.atttypid, a.atttypmod)) end,
                      ', ' order by a.attnum)
      into kol, uttr
    from pg_attribute a
    where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped and a.attname <> 'id'
      and exists (select 1 from pg_attribute b where b.attrelid = ('pg_temp.s_' || t)::regclass and b.attname = a.attname);
    if t = 'besok' then
      villkor := 'm.ny is not null';
      finns := 'select 1 from public.besok x where x.user_id = m.ny and x.objekt_id = s.objekt_id'
            || ' and x.scheme is not distinct from nullif(s.scheme, '''') and x.datum = s.datum::timestamptz';
    else
      villkor := 'true';
      finns := 'select 1 from public.meddelanden x where x.skapad = s.skapad::timestamptz and x.meddelande = s.meddelande';
    end if;
    if v_epost <> '' then villkor := villkor || format(' and lower(m.epost) = lower(%L)', v_epost); end if;
    execute format('select count(*) from pg_temp.%I', 's_' || t) into tot;
    execute format('insert into public.%I (%s) select %s from pg_temp.%I s left join anvkarta m'
                || ' on m.gammal = nullif(s.user_id, %L)::uuid where %s and not exists (%s)',
                   t, kol, uttr, 's_' || t, '', villkor, finns);
    get diagnostics n = row_count;
    raise notice '%: % i kopian, % återställda', t, tot, n;
  end loop;
end $$;

alter table public.meddelanden enable trigger user;

-- Världsarv: kopior från före 2026-10-08 har namnet som nyckel – översätt till UNESCO-numret (23_varldsarv_unesco.sql)
do $$
declare n bigint;
begin
  update public.besok b set objekt_id = o.ext_id
  from public.objekt o
  where b.scheme = 'VA' and o.kalla = 'VA' and b.objekt_id = o.namn and b.objekt_id !~ '^[0-9]+$';
  get diagnostics n = row_count;
  if n > 0 then raise notice 'världsarv: % besök översatta från namn till UNESCO-nummer', n; end if;
end $$;

-- Medaljer: läggs tillbaka på rätt konto (via e-post). Finns medaljen redan (samma cup och period) ändras den inte.
do $$
declare n bigint; tot bigint; v_epost text := current_setting('aterstall.epost');
begin
  if to_regclass('pg_temp.s_medaljer') is null then raise notice 'medaljer: finns inte i kopian'; return; end if;
  select count(*) into tot from s_medaljer;
  insert into public.medaljer (user_id, cup, tid, period, plats, antal, deltagare, utdelad)
  select m.ny, s.cup, s.tid, s.period::date, s.plats::int, s.antal::int, s.deltagare::int, coalesce(nullif(s.utdelad, '')::timestamptz, now())
  from s_medaljer s join anvkarta m on m.gammal = s.user_id::uuid
  where (v_epost = '' or lower(m.epost) = lower(v_epost))
  on conflict (user_id, cup, tid, period) do nothing;
  get diagnostics n = row_count;
  raise notice 'medaljer: % i kopian, % återställda', tot, n;
end $$;

-- Grupper (2026-10-08): gruppen läggs tillbaka med samma id, namn och kod om den inte finns (och namnet/koden är ledigt);
-- medlemskap och upplåsta nivåer läggs tillbaka på rätt konto. Vid återställning av en enskild användare
-- tas bara den användarens medlemskap (och grupper hen är med i) med.
do $$
declare n1 bigint := 0; n2 bigint := 0; n3 bigint := 0; v_epost text := current_setting('aterstall.epost');
begin
  if to_regclass('pg_temp.s_grupper') is null then raise notice 'grupper: finns inte i kopian'; return; end if;
  insert into public.grupper (id, namn, kod, skapad, skapad_av)
  select s.id::uuid, s.namn, s.kod, s.skapad::timestamptz, (select m.ny from anvkarta m where m.gammal = nullif(s.skapad_av, '')::uuid)
  from s_grupper s
  where exists (select 1 from s_grupp_medlemmar sm join anvkarta m on m.gammal = sm.user_id::uuid
                where sm.grupp_id = s.id and (v_epost = '' or lower(m.epost) = lower(v_epost)))
    and not exists (select 1 from public.grupper g where g.kod = s.kod or lower(btrim(g.namn)) = lower(btrim(s.namn)))
  on conflict (id) do nothing;
  get diagnostics n1 = row_count;
  insert into public.grupp_medlemmar (grupp_id, user_id, roll, gick_med)
  select sm.grupp_id::uuid, m.ny, sm.roll, sm.gick_med::timestamptz
  from s_grupp_medlemmar sm join anvkarta m on m.gammal = sm.user_id::uuid
  where (v_epost = '' or lower(m.epost) = lower(v_epost))
    and exists (select 1 from public.grupper g where g.id = sm.grupp_id::uuid)
  on conflict (grupp_id, user_id) do nothing;
  get diagnostics n2 = row_count;
  if to_regclass('pg_temp.s_befogenheter') is not null then
    insert into public.befogenheter (user_id, niva, notering, satt)
    select m.ny, s.niva::int, nullif(s.notering, ''), s.satt::timestamptz
    from s_befogenheter s join anvkarta m on m.gammal = s.user_id::uuid
    where (v_epost = '' or lower(m.epost) = lower(v_epost))
    on conflict (user_id) do nothing;
    get diagnostics n3 = row_count;
  end if;
  raise notice 'grupper: % återställda, % medlemskap, % upplåsta nivåer', n1, n2, n3;
end $$;

\echo '=== Så här ser det ut efteråt ==='
select (select count(*) from public.profiler) as profiler, (select count(*) from public.besok) as besok,
       (select count(*) from public.meddelanden) as meddelanden, (select count(*) from public.medaljer) as medaljer,
       (select count(*) from public.grupper) as grupper;
