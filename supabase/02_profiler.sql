-- Profiler skapas automatiskt för varje ny användare + användarnamn.
-- Kör i SQL Editor efter 01_schema.sql. Går att köra om.

-- Skapa profilrad när någon registrerar sig (första inloggningen)
create or replace function public.ny_profil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiler (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists ny_anvandare on auth.users;
create trigger ny_anvandare after insert on auth.users
  for each row execute function public.ny_profil();

-- Profiler för användare som redan finns
insert into public.profiler (id) select id from auth.users on conflict (id) do nothing;

-- Användarnamn: 2–30 tecken och unikt (oberoende av stora/små bokstäver)
alter table public.profiler drop constraint if exists profiler_namn_langd;
alter table public.profiler add constraint profiler_namn_langd
  check (namn is null or char_length(trim(namn)) between 2 and 30);
create unique index if not exists profiler_namn_unik on public.profiler (lower(trim(namn)));
