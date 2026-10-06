-- Naturminnen (NV, kalla = NM). Kör i SQL Editor INNAN tools/ladda_naturminnen.sh. Går att köra om.
-- Naturminnen är NV-objekt med NVR-id som ext_id – besök kan därför också vara kopplade via besok.nvrid.
create or replace function public.objekt_besokt(p_kalla text, p_ext_id text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from public.besok b where b.scheme = p_kalla and b.objekt_id = p_ext_id)
      or (p_kalla in ('NR', 'NP', 'KR', 'NM') and exists (select 1 from public.besok b where b.nvrid = p_ext_id));
$$;
revoke execute on function public.objekt_besokt(text, text) from public, anon, authenticated;
