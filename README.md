# Hit och dit – naturbesök

Webbapp som tar din position, visar vilka skyddade områden du står i (Naturvårdsverkets öppna geodata) och loggar besöket. Inloggning och lagring i Supabase.

**App:** https://lunkster.github.io/hitochdit/
Testa utan GPS: `https://lunkster.github.io/hitochdit/?lat=59.33&lon=18.07`

## Filer
| Fil | Vad |
| --- | --- |
| `index.html` | Hela appen (HTML, CSS, JS). Publiceras via GitHub Pages. |
| `supabase/01_schema.sql` | Tabeller och Row Level Security i Supabase. Körs i SQL Editor. |
| `supabase/02_profiler.sql` | Automatisk profil vid registrering, unika användarnamn. |
| `supabase/03_radera_konto.sql` | Funktion så att användare kan radera sitt eget konto. |
| `supabase/04_kontakt.sql` | Kontaktformulär + avisering via ntfy (ämnet fylls i vid körning, ligger inte i repot). |
| `supabase/05_version_efterhand.sql` | Kolumn `pa_plats` för efterhandsbesök, version i meddelanden. |
| `supabase/06_geodata.sql` | PostGIS, tabellen `objekt` (alla egna geodata) och funktionerna `objekt_vid` / `objekt_geom`. |
| `supabase/07_objekt_url.sql` | Länk till källans objektsida i `objekt_vid`/`objekt_geom`. |
| `supabase/ladda/*.sql` | Flyttar data från `import`-schemat till `objekt` efter ogr2ogr. |
| `tools/ladda_*.sh` | Laddar en datamängd från källans WFS till Supabase med ogr2ogr. Kräver `~/.config/hitochdit/db.env` (se `tools/db.env.exempel`). |
| `tools/geodata_status.sh` | Visar antal objekt och databasens storlek. |
| `apps-script/Code.gs` | Gamla Google Sheets-lagringen (ersatt av Supabase 2026-10, tas bort). |

## Datakällor
- WFS `https://geodata.naturvardsverket.se/inspire/ps/wfs` – träff på skyddat område vid position
- WMS `https://geodata.naturvardsverket.se/inspire/ps-nvr/ows` – kartskikt för naturreservat och nationalparker, besökta färgas med SLD + CQL-filter
- Bakgrund: OpenTopoMap, Esri World Imagery

## Version
Konstanten `VERSION` överst i skriptet i `index.html` höjs vid varje ändring: `0.MINOR.0` för nya funktioner, `0.x.PATCH` för rättningar. Visas under ⓘ och ⚙ och skickas med kontaktmeddelanden.

## Arbetsflöde
```bash
git pull                      # hämta senaste (om du ändrat på GitHub)
git add -A
git commit -m "Vad som ändrats"
git push                      # publiceras på GitHub Pages efter någon minut
```
