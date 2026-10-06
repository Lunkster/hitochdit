-- Används av tools/aterstall.sh (körs inom en transaktion som skriptet avslutar med commit eller rollback).
-- Förutsätter tillfälliga tabeller s_konton, s_profiler, s_besok, s_meddelanden (text-kolumner) från kopian
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

\echo '=== Så här ser det ut efteråt ==='
select (select count(*) from public.profiler) as profiler, (select count(*) from public.besok) as besok,
       (select count(*) from public.meddelanden) as meddelanden;
