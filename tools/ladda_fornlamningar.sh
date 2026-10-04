#!/usr/bin/env bash
# Laddar fornlämningar (antikvarisk bedömning = Fornlämning) från Riksantikvarieämbetet till Supabase (kalla = FL).
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_fornlamningar.sh
# Stor datamängd – kan ta 10–30 minuter. Datorn får inte somna under tiden.
source "$(dirname "$0")/geodata.sh"

RAA="https://inspire-raa.metria.se/geoserver/Kulturhistoriska_lamningar/wfs"
FILTER="antikvariskbedomning = 'Fornlämning'"
ladda_wfs "$RAA" "kulturhistoriska_fornlamningar_point"   "fl_punkt" "$FILTER"
ladda_wfs "$RAA" "kulturhistoriska_fornlamningar_line"    "fl_linje" "$FILTER"
ladda_wfs "$RAA" "kulturhistoriska_fornlamningar_polygon" "fl_yta"   "$FILTER"
kor_sql "supabase/ladda/fornlamningar.sql"
echo "✓ Klart. Kontrollera storleken: bash $(dirname "$0")/geodata_status.sh"
