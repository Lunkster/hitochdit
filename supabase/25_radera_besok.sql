-- Rättning 2026-10-08: det gick inte att ta bort egna besök sedan 20_sakerhet.sql (2026-10-07).
-- 20_sakerhet.sql drog av misstag in DELETE på besok för inloggade (kommentaren där säger att den ska finnas kvar).
-- Policyn "besok: radera egna" (01_schema.sql) begränsar fortfarande till egna rader. Går att köra om.
grant delete on public.besok to authenticated;
