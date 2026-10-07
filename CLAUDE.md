# Hit och Dit – instruktioner för Claude

Webbapp för att logga besök i Sveriges skyddade natur och kulturmiljöer (naturreservat, nationalparker, världsarv,
byggnadsminnen, fornlämningar, kyrkor, fyrar …) utifrån telefonens position. Hobbyprojekt av Henrik Lundqvist, steg 1
av idén *Myndighetsgamification*. Svara och skriv på **svenska**.

## Dokumentation (Obsidian, källan till sanning för planering)
Valvet: `~/Dropbox/Projekt/Obsidian/Projekt/Hit och Dit/`
- `Naturapp.md` – status, **önskelista (inkorg)**, **tågordning**, logg. Läs önskelistan i början av varje arbetspass och sortera in i tågordningen.
- `Hit och Dit - Geodata.md` – geodatabasen: datamängder, laddkommandon, storlek, felsökning
- `Naturapp - Supabase.md` – databas, inloggning, SQL-filer, ntfy
- `Hit och Dit - Backup.md` – säkerhetskopior (`tools/backup.sh`) och återställning (`tools/aterstall.sh`)
- `Hit och Dit - Infotext.md` – texten under ⓘ (måste stämma med `index.html`)
- `Appidé_ Turf möter Artportalen.md`, `Myndighetsgamification.md` – idé och vision

Efter varje ändring: uppdatera tågordningen (bocka av / *ska testas*) och lägg en rad i loggen i `Naturapp.md`.

## Teknik
- **Frontend:** en enda fil, `index.html` (HTML + CSS + vanilla JS, Leaflet 1.9.4 via cdnjs, supabase-js v2 via jsDelivr). Inget byggsteg, inga npm-paket.
- **Drift:** GitHub Pages, `https://lunkster.github.io/hitochdit/` (repo `Lunkster/hitochdit`).
- **Backend:** Supabase (Postgres + PostGIS + Auth med e-postlänk). Tabeller `besok`, `profiler`, `meddelanden`, `objekt`. Row Level Security på allt.
- **Geodata:** visning från källornas WMS (Naturvårdsverket, RAÄ); positionsmatchning mot egen tabell `objekt` via RPC `objekt_vid`, `objekt_geom`, `objekt_i_ruta`, `objekt_ytor_i_ruta`, `objekt_nara` (I närheten). Källkoder i `objekt.kalla`: NR, NP, KR, NM, VA, BM, FL, KY, KO, FY (natur/kultur), TA, SJ, OE, TO (geografi, 300-listor med `egenskaper.rang`; toppar även `lanrang` och `rangtext`).
- **Uppdatering av objekt:** upsert på `(kalla, ext_id)`; borttagna rensas med `public.objekt_stada()` – besökta objekt ligger kvar med `egenskaper.utgatt` och ger inga nya träffar.
- **Laddning av geodata:** `tools/ladda_*.sh` (ogr2ogr + psql) körs av Henrik på hans dator. Varje skript kör sin `supabase/ladda/*.sql` automatiskt.

## Regler
- **Version:** höj `VERSION` / `VERSION_DATUM` överst i skriptet i `index.html` vid varje ändring (`0.MINOR.0` funktion, `0.x.PATCH` rättning). Aktuell version står också i `Naturapp.md`.
- **Hemligheter:** aldrig databaslösenord, service-/secret-nycklar eller ntfy-ämnet i repot (repot är publikt). Publishable key och projekt-URL får ligga i `index.html`.
- **SQL:** spara alltid som numrerad fil i `supabase/` (`NN_namn.sql`, nästa lediga nummer) som går att köra om. Claude kör filen via Supabase-anslutningen (`apply_migration`, projekt `jihglrfinqsmigpxzfhk`) efter Henriks godkännande – annars körs den i SQL Editor. `apply_migration` hänger (tidsgräns) – använd `execute_sql`, och undvik `revoke all`, `drop …` och `update`/`delete` utan `where` (kräver en bekräftelse som inte visas); skriv `create or replace trigger`, uppräknade rättigheter och `where`. Testa som appen med `begin; set local role authenticated; … rollback;`. Filer i `supabase/ladda/` körs bara av laddskripten. `VACUUM` kan inte köras i SQL Editor – använd `tools/geodata_stada.sh`.
- **Git:** Claude ändrar filer; Henrik gör `git add/commit/push` själv. Ge ett färdigt commit-meddelande i formatet `vX.Y.Z: kort beskrivning`.
- **Nät:** RAÄ:s WFS tillåter inte anrop från webbsidor (CORS) – hämta via egen databas. NV:s WFS/WMS fungerar direkt.
- **Testa före leverans:** `node --check` på skriptet och en snabb körning i headless Chromium (kartbibliotek/nät kan saknas – appen ska ändå ladda utan fel).
- **Integritet:** ändringar som påverkar vilka uppgifter som sparas eller skickas vidare ska speglas i infotexten (ⓘ) och i `Hit och Dit - Infotext.md`.
- **Stil:** appens färger finns som CSS-variabler i `:root` (ljust) och `[data-theme=dark]` (mörkt). Knappgrön `#4f6b4a`, besökt `#c2410c`.
