#!/usr/bin/env bash
# Laddar enskilda och statliga byggnadsminnen (skyddsområden) från Riksantikvarieämbetet till Supabase (kalla = BM).
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_byggnadsminnen.sh
source "$(dirname "$0")/geodata.sh"

ladda_wfs "https://inspire-raa.metria.se/geoserver/Bebyggelse/wfs" "byggnadsminnen_skyddsomraden" "byggnadsminnen"
kor_sql "supabase/ladda/byggnadsminnen.sql"
echo "✓ Klart."
