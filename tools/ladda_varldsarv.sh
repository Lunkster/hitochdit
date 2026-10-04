#!/usr/bin/env bash
# Laddar Sveriges världsarv från Riksantikvarieämbetet till Supabase (tabellen objekt, kalla = VA).
# Kör från valfri mapp:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_varldsarv.sh
source "$(dirname "$0")/geodata.sh"

ladda_wfs "https://inspire-raa.metria.se/geoserver/Varldsarv_ogc/wfs" "varldsarv_sverige" "varldsarv"
kor_sql "supabase/ladda/varldsarv.sql"
echo "✓ Klart."
