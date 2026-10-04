#!/usr/bin/env bash
# Packar ihop tabellen objekt och lämnar tillbaka ledig plats (VACUUM FULL), visar sedan storleken.
# Kör efter stora laddningar/borttag:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/geodata_stada.sh
# VACUUM kan inte köras i Supabase SQL Editor (den kör allt i en transaktion) – därför via psql här.
source "$(dirname "$0")/geodata.sh"
echo "→ Packar ihop public.objekt (kan ta någon minut, tabellen är låst under tiden)"
psql "$HITOCHDIT_DB" -q -c "vacuum full analyze public.objekt;"
bash "$(dirname "$0")/geodata_status.sh"
