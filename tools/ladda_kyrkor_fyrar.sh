#!/usr/bin/env bash
# Laddar kyrkobyggnader (KY) och fyrar (FY) ur RAÄ:s kulturhistoriskt inventerade bebyggelse till Supabase.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_kyrkor_fyrar.sh
source "$(dirname "$0")/geodata.sh"

# Hämtar bara kyrkliga kulturminnen och sådant som har med fyrar att göra; urvalet finslipas i SQL-steget
ladda_wfs "https://inspire-raa.metria.se/geoserver/Bebyggelse/wfs" "kulturhistoriskt_inventerad_bebyggelse" "bebyggelse" \
  "kyrkligt_kulturminnestyp_namn IS NOT NULL OR andamal_underkategori LIKE '%yr%' OR sekundart_andamal LIKE '%yr%' OR namn LIKE '%yr%'"
kor_sql "supabase/ladda/kyrkor_fyrar.sql"
echo "✓ Klart."
