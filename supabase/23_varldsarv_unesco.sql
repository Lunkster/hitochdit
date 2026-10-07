-- Världsarvens nyckel: UNESCO-nummer i stället för svenskt namn (tål namnbyten). 2026-10-08. Körd via Claude.
-- Numret tas ur UNESCO-länken (…/list/555). Besök flyttas med. Går att köra om (gör inget om nycklarna redan är nummer).

-- 1. Objekten
update public.objekt o
set ext_id = substring(o.egenskaper->>'url' from '/list/([0-9]+)'), uppdaterad = now()
where o.kalla = 'VA' and o.ext_id !~ '^[0-9]+$' and substring(o.egenskaper->>'url' from '/list/([0-9]+)') is not null;

-- 2. Besöken (gamla nyckeln = namnet). Triggrarna räknar om verifierad/kommun – datumen ändras inte (körs som postgres).
update public.besok b
set objekt_id = o.ext_id
from public.objekt o
where b.scheme = 'VA' and o.kalla = 'VA' and b.objekt_id = o.namn and b.objekt_id !~ '^[0-9]+$';

-- Kontroll
select o.ext_id as unesco, o.namn, (select count(*) from public.besok b where b.scheme = 'VA' and b.objekt_id = o.ext_id) as besok
from public.objekt o where o.kalla = 'VA' order by o.ext_id::int;
