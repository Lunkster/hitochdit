# Hit och dit – naturbesök

Webbapp som tar din position, visar vilka skyddade områden du står i (Naturvårdsverkets öppna geodata) och loggar besöket.

**App:** https://lunkster.github.io/hitochdit/
Testa utan GPS: `https://lunkster.github.io/hitochdit/?lat=59.33&lon=18.07`

## Filer
| Fil | Vad |
| --- | --- |
| `index.html` | Hela appen (HTML, CSS, JS). Publiceras via GitHub Pages. |
| `apps-script/Code.gs` | Kopia av Apps Script-koden i Google Sheet som tar emot och läser besök. Ändringar här måste klistras in i Apps Script och publiceras som ny version. |

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
