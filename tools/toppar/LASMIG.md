# Toppar – 300 högsta + 5 högsta per län
Underlag (utanför repot, i `~/Dokument/Claude/HitochDit/kod/`): Lantmäteriets Topografi 100 `hojd_sverige/hojd_sverige_topo100.gpkg`
(höjdpunkter + höjdkurvor 10 m) och textlagren för namn: **Topografi 10** `~/Dokument/Geodata/LM Topo10/text_sverige.gpkg` (i första hand, `HITOCHDIT_TOPO10`) och Topografi 50 `text_sverige/text_sverige.gpkg` (komplement). Bara Pythons standardbibliotek.

| Steg | Kommando | Resultat |
| --- | --- | --- |
| 1. Toppanalys | `python3 analys.py` (några minuter, kan avbrytas och köras vidare) | `kod/toppar_resultat.csv` |
| 2. Reservregel | `python3 reserv.py` | kolumnen `reserv` i samma fil |
| 3. Urval + namn | `python3 namn.py` | `kod/toppar.csv` – låsta namn behålls via objektidentitet: handrättade i `Toppar.gpkg`, handrättade/OSM i `Toppar_v2.gpkg`, Wikipedia (Kaskasatjåkka, Kaskasapakte) |
| 4. GeoPackage | `python3 skriv_gpkg.py Toppar_v3.gpkg` | `kod/Toppar_v3.gpkg` (öppna/rätta i QGIS) |
| 5. Namn från OSM | `python3 osm_namn.py` (förslag) → `python3 osm_namn.py --spara` | namn till toppar som saknar namn, `kod/toppar_osm_forslag.csv` |
| 6. Till databasen | `bash ../ladda_toppar.sh` | tabellen `objekt`, kalla TO |

**Topp** = höjdpunkten ligger inne i närmaste slutna höjdkurva under sig och inget högre finns innanför den.
**Primärfaktor > 30 m** = samma test på kurvan minst 30 m lägre. Kurvor som slutar vid riksgränsen stängs med en rak linje.
**Reservregel** (kurvorna gick inte att sluta): ingen högre kurva/punkt inom 1 km och närmaste högre höjdpunkt minst 1,5 km bort → räknas, `prim30 = okänd`.

**Namnregler:** topplika namn (*…berget, …kullen, …tjåhkkå, …bákte, …toppen*) inom 2 km; andra terrängnamn bara inom 300 m (800 m över 800 m höjd, där nästan alla namn är bergsnamn). Gårds-, skogs-, myr- och ängsnamn sorteras bort. Inget namn → stort bergsnamn (stor text) inom 4 km. Deltoppar får bergets namn framför. Samma namn på flera toppar → den högsta.
