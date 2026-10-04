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
| `apps-script/Code.gs` | Gamla Google Sheets-lagringen (ersatt av Supabase 2026-10, tas bort). |

## Datakällor
- WFS `https://geodata.naturvardsverket.se/inspire/ps/wfs` – träff på skyddat område vid position
- WMS `https://geodata.naturvardsverket.se/inspire/ps-nvr/ows` – kartskikt för naturreservat och nationalparker, besökta färgas med SLD + CQL-filter
- Bakgrund: OpenTopoMap, Esri World Imagery

## Arbetsflöde
```bash
git pull                      # hämta senaste (om du ändrat på GitHub)
git add -A
git commit -m "Vad som ändrats"
git push                      # publiceras på GitHub Pages efter någon minut
```
