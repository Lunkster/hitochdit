-- Version i kontaktmeddelanden + efterhandsloggning av besök.
-- Kör i SQL Editor. Går att köra om.

-- Efterhandsloggning: sant = loggat med GPS på plats, falskt = loggat i efterhand.
-- Befintliga besök räknas som på plats. Efterhandsbesök räknas inte i framtida topplistor/poäng.
alter table public.besok add column if not exists pa_plats boolean not null default true;

-- Appversion i kontaktmeddelanden
alter table public.meddelanden add column if not exists version text;
alter table public.meddelanden drop constraint if exists meddelanden_version_langd;
alter table public.meddelanden add constraint meddelanden_version_langd check (version is null or char_length(version) <= 30);
