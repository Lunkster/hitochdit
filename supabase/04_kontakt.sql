-- Kontaktformulär + avisering till mobilen via ntfy.
-- Kör i SQL Editor. Går att köra om.
-- OBS: byt ut DITT-NTFY-AMNE nedan mot ditt hemliga ämne INNAN du kör.
--      Ämnet ska inte ligga i GitHub (repot är publikt).

-- ============ Tabell ============
create table if not exists public.meddelanden (
  id          bigint generated always as identity primary key,
  skapad      timestamptz not null default now(),
  user_id     uuid default auth.uid() references auth.users on delete set null,
  epost       text,                       -- frivillig, för svar
  meddelande  text not null,
  hanterad    boolean not null default false
);
alter table public.meddelanden drop constraint if exists meddelanden_langd;
alter table public.meddelanden add constraint meddelanden_langd
  check (char_length(trim(meddelande)) between 2 and 3000 and (epost is null or char_length(epost) <= 200));

alter table public.meddelanden enable row level security;
-- Alla (även utloggade) får skicka. Ingen policy för select/update/delete = ingen kan läsa via appen.
drop policy if exists "meddelanden: alla kan skicka" on public.meddelanden;
create policy "meddelanden: alla kan skicka" on public.meddelanden
  for insert to anon, authenticated
  with check (user_id is null or user_id = (select auth.uid()));

-- ============ Avisering via ntfy (https://ntfy.sh) ============
-- Skickar hela meddelandet (max ~1500 tecken) och ev. e-post till ntfy, med en Svara-knapp (mailto).
-- Obs: innehållet passerar då ntfy.sh och cachas där en kort tid – står i integritetstexten.
create extension if not exists pg_net with schema extensions;

create or replace function public.avisera_meddelande() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  text_ut text := left(new.meddelande, 1500) || case when char_length(new.meddelande) > 1500 then ' …' else '' end;
  knappar jsonb := '[]'::jsonb;
begin
  if new.epost is not null then
    text_ut := text_ut || E'\n\n— ' || new.epost;
    knappar := jsonb_build_array(jsonb_build_object(
      'action', 'view', 'label', 'Svara',
      'url', 'mailto:' || new.epost || '?subject=' || replace('Hit och Dit – ditt meddelande', ' ', '%20')));
  end if;
  perform net.http_post(
    url  := 'https://ntfy.sh',
    body := jsonb_build_object(
      'topic',   'DITT-NTFY-AMNE',
      'title',   'Hit och Dit – meddelande #' || new.id,
      'message', text_ut,
      'tags',    jsonb_build_array('envelope'),
      'actions', knappar
    )
  );
  return new;
end $$;

drop trigger if exists nytt_meddelande on public.meddelanden;
create trigger nytt_meddelande after insert on public.meddelanden
  for each row execute function public.avisera_meddelande();
