#!/usr/bin/env bash
# Kompletterar kyrkorna med Svenska kyrkans kyrkor från OpenStreetMap där RAÄ saknar dem (kalla = KO, typ Kyrka).
# Kör ALLTID efter ladda_kyrkor_fyrar.sh, så att dubbletter mot RAÄ sorteras bort.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_osm_kyrkor.sh
source "$(dirname "$0")/geodata.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 "$REPO/tools/osm_kyrkor.py" "$TMP/osm_kyrkor.csv"
psql "$HITOCHDIT_DB" -v ON_ERROR_STOP=1 -q <<SQL
create schema if not exists import;
drop table if exists import.osm_kyrkor;
create table import.osm_kyrkor (osm_id text, namn text, lat double precision, lon double precision, denomination text, operator text, regel text);
\copy import.osm_kyrkor from '$TMP/osm_kyrkor.csv' with (format csv, header true)
SQL
kor_sql "supabase/ladda/osm_kyrkor.sql"
echo "✓ Klart."
