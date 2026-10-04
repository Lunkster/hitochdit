#!/usr/bin/env bash
# Laddar naturreservat, nationalparker och kulturreservat från Naturvårdsverket till Supabase (kalla = NR, NP, KR).
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_nv.sh
# Tar några minuter – naturreservaten är ca 6 000 detaljerade ytor.
source "$(dirname "$0")/geodata.sh"

NV="https://geodata.naturvardsverket.se/inspire/ps-nvr/ows"
ladda_wfs "$NV" "PS.ProtectedSites.NR" "nv_nr"
ladda_wfs "$NV" "PS.ProtectedSites.NP" "nv_np"
ladda_wfs "$NV" "PS.ProtectedSites.KR" "nv_kr"
kor_sql "supabase/ladda/nv.sql"
echo "✓ Klart. Har du besök sedan tidigare? Kör en gång: supabase/08_koppla_om_nv_besok.sql i SQL Editor."
