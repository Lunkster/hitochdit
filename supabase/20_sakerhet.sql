-- Säkerhetsgenomgång 2026-10-07 (se Naturapp.md, logg). Körd 2026-10-07 via Claude (execute_sql). Går att köra om.
-- Skrivet utan 'revoke all', 'drop' och update utan where – Supabase-anslutningen kräver annars en extra bekräftelse som inte visas.
-- Row Level Security var redan rätt på alla tabeller. Det här stramar åt runtom och förbereder topplistorna.

-- 1. Triggerfunktioner ska inte gå att anropa via API:t (/rest/v1/rpc/...). Triggrar fungerar ändå –
--    rätten kontrolleras bara när triggern skapas.
revoke execute on function public.avisera_meddelande() from public, anon, authenticated;
revoke execute on function public.ny_profil() from public, anon, authenticated;
revoke execute on function public.besok_satt_indelning() from public, anon, authenticated;

-- 2. Tabellrättigheter: bara det appen faktiskt använder (RLS gäller dessutom radvis).
--    TRUNCATE omfattas inte av RLS – tas bort överallt.
--    Kvar efteråt: objekt/indelning select (alla); meddelanden insert (alla); profiler select/insert/update (inloggade);
--    besok select/insert/delete (inloggade) + select för anon (ger inga rader – RLS gäller bara inloggade – men objekt_i_omrade får inte fel).
revoke insert, update, delete, truncate, references, trigger on public.objekt, public.indelning from anon, authenticated;
revoke update, truncate, references, trigger on public.besok from anon, authenticated;   -- delete ska finnas kvar för inloggade (rättat 2026-10-08, se 25_radera_besok.sql)
revoke insert, delete on public.besok from anon;
revoke update, truncate, references, trigger on public.meddelanden from anon, authenticated;
revoke select, delete on public.meddelanden from anon, authenticated;
revoke delete, truncate, references, trigger on public.profiler from anon, authenticated;
revoke select, insert, update on public.profiler from anon;

-- 3. Besök: servern sätter datum och avgör om ett på-plats-besök är verifierat (för topplistorna).
--    Verifierat = loggat på plats, med position, inom 100 m från objektet (+ GPS-osäkerheten, högst 200 m).
alter table public.besok add column if not exists verifierad boolean not null default false;

create or replace function public.besok_kontroll() returns trigger
language plpgsql set search_path = public, extensions as $$
declare pt extensions.geometry; d double precision;
begin
  -- Från appen (anon/authenticated): inget datum i framtiden, och på plats = nu (går inte att bakdatera).
  -- Laddskript och återställning (postgres) behåller sina datum.
  if current_user in ('anon', 'authenticated') then
    if new.datum is null or new.datum > now() then new.datum := now(); end if;
    if new.pa_plats and tg_op = 'INSERT' then new.datum := now(); end if;
  end if;
  if new.pa_plats then
    if new.lat between 55 and 70 and new.lon between 10 and 25 then
      pt := ST_SetSRID(ST_MakePoint(new.lon, new.lat), 4326);
      -- Två separata uppslag så att indexet på (kalla, ext_id) används (en OR läser hela tabellen)
      select min(x) into d from (
        select ST_Distance(o.geom::geography, pt::geography) as x
        from public.objekt o where o.kalla = new.scheme and o.ext_id = new.objekt_id
        union all
        select ST_Distance(o.geom::geography, pt::geography)
        from public.objekt o where new.nvrid is not null and o.kalla in ('NR', 'NP', 'KR', 'NM') and o.ext_id = new.nvrid) s;
    end if;
  end if;
  new.verifierad := coalesce(new.pa_plats and d <= least(100 + greatest(coalesce(new.acc, 0), 0), 200), false);
  return new;
end $$;
revoke execute on function public.besok_kontroll() from public, anon, authenticated;

create or replace trigger besok_kontroll before insert or update of lat, lon, acc, objekt_id, scheme, nvrid, pa_plats, datum on public.besok
  for each row execute function public.besok_kontroll();

-- Befintliga besök: räkna fram verifierad via triggern (körs som postgres, så datumen lämnas orörda)
update public.besok set pa_plats = pa_plats where id > 0 and pa_plats;

-- 4. Kontaktformuläret: spärr mot översvämning (spam och ntfy-aviseringar) – högst 10 meddelanden per 10 minuter totalt.
create or replace function public.meddelanden_sparr() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.meddelanden m where m.skapad > now() - interval '10 minutes') >= 10 then
    raise exception 'För många meddelanden just nu – försök igen om en stund.';
  end if;
  return new;
end $$;
revoke execute on function public.meddelanden_sparr() from public, anon, authenticated;
-- "a_" så att den körs före aviseringen (triggrar körs i namnordning)
create or replace trigger a_meddelanden_sparr before insert on public.meddelanden
  for each row execute function public.meddelanden_sparr();
