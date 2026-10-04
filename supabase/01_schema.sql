-- Naturapp / hitochdit – grundschema i Supabase
-- Kör hela filen i Supabase: SQL Editor → New query → klistra in → Run.
-- Filen går att köra om (if not exists / drop policy if exists).

-- ============ Profiler (visningsnamn för framtida topplistor) ============
create table if not exists public.profiler (
  id      uuid primary key references auth.users on delete cascade,
  namn    text,
  skapad  timestamptz not null default now()
);
alter table public.profiler enable row level security;

drop policy if exists "profiler: alla inloggade kan läsa" on public.profiler;
create policy "profiler: alla inloggade kan läsa" on public.profiler
  for select to authenticated using (true);
drop policy if exists "profiler: skapa egen" on public.profiler;
create policy "profiler: skapa egen" on public.profiler
  for insert to authenticated with check ((select auth.uid()) = id);
drop policy if exists "profiler: ändra egen" on public.profiler;
create policy "profiler: ändra egen" on public.profiler
  for update to authenticated using ((select auth.uid()) = id);

-- ============ Besök ============
create table if not exists public.besok (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  datum      timestamptz not null default now(),
  objekt_id  text not null,          -- INSPIRE localId (Natura 2000 utan .1/.2)
  scheme     text,                   -- t.ex. IUCN, natura2000
  nvrid      text,                   -- Naturvårdsverkets NVR-id (stabil nyckel)
  namn       text not null,
  typ        text not null,          -- Naturreservat, Nationalpark, Natura 2000 …
  lat        double precision,
  lon        double precision,
  acc        integer
);
create index if not exists besok_user_datum on public.besok (user_id, datum desc);
create index if not exists besok_nvrid on public.besok (nvrid);

alter table public.besok enable row level security;

drop policy if exists "besok: läsa egna" on public.besok;
create policy "besok: läsa egna" on public.besok
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "besok: skapa egna" on public.besok;
create policy "besok: skapa egna" on public.besok
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "besok: radera egna" on public.besok;
create policy "besok: radera egna" on public.besok
  for delete to authenticated using ((select auth.uid()) = user_id);
