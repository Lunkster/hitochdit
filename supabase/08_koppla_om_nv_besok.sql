-- Kopplar om befintliga besök i naturreservat/nationalparker från den gamla modellen (scheme 'IUCN')
-- till geodatabasen (scheme 'NR'/'NP', objekt_id = NVR-id). Kör EN gång i SQL Editor efter tools/ladda_nv.sh.
-- Inga besök tas bort. Går att köra om (gör inget andra gången).

-- 1. Besök som har NVR-id
update public.besok b
set scheme = o.kalla, objekt_id = o.ext_id
from public.objekt o
where b.scheme = 'IUCN' and b.nvrid is not null
  and o.kalla in ('NR', 'NP', 'KR') and o.ext_id = b.nvrid;

-- 2. Äldre besök utan NVR-id: matcha på typ + namn när namnet är unikt
update public.besok b
set scheme = o.kalla, objekt_id = o.ext_id, nvrid = o.ext_id
from public.objekt o
where b.scheme = 'IUCN' and b.nvrid is null
  and o.kalla = case b.typ when 'Naturreservat' then 'NR' when 'Nationalpark' then 'NP' end
  and lower(o.namn) = lower(b.namn)
  and (select count(*) from public.objekt o2 where o2.kalla = o.kalla and lower(o2.namn) = lower(b.namn)) = 1;

-- Kvar som inte kunde kopplas (fungerar fortfarande, men på gamla sättet):
select typ, namn, nvrid, datum from public.besok where scheme = 'IUCN' order by datum desc;
