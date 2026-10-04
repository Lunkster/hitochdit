-- Låter en inloggad användare radera sitt eget konto (GDPR – rätten att bli raderad).
-- Raderar raden i auth.users; profil och alla besök följer med via "on delete cascade".
-- Kör i SQL Editor. Går att köra om.

create or replace function public.radera_mitt_konto() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Inte inloggad';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.radera_mitt_konto() from public, anon;
grant execute on function public.radera_mitt_konto() to authenticated;
