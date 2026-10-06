#!/usr/bin/env bash
# Laddar naturminnen från Naturvårdsverket till Supabase (tabellen objekt, kalla = NM).
# Kräver att supabase/12_geografi.sql och 14_naturminnen.sql körts en gång, och att kommuner är laddade.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_naturminnen.sh
source "$(dirname "$0")/geodata.sh"

ladda_wfs "https://geodata.naturvardsverket.se/inspire/ps-nvr/ows" "PS.ProtectedSites.NM" "nv_nm"
kor_sql "supabase/ladda/naturminnen.sql"
echo "✓ Klart."
