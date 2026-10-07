#!/usr/bin/env bash
# Säkerhetskopia av användardata i Supabase: besök, profiler, kontaktmeddelanden, medaljer och konton (id + e-post).
# Geodatan (objekt, indelning) tas inte med – den laddas om med tools/ladda_*.sh.
# Sparas UTANFÖR repot (personuppgifter): ~/Dokument/Claude/HitochDit/backup/ (ändra med HITOCHDIT_BACKUP i db.env).
# Behåller de senaste 60 kopiorna. Körs automatiskt varje dag om du kört tools/backup_installera.sh.
# Kör för hand:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/backup.sh
set -euo pipefail
KONF="${HOME}/.config/hitochdit/db.env"
[[ -f "$KONF" ]] || { echo "Saknar $KONF" >&2; exit 1; }
# shellcheck disable=SC1090
source "$KONF"
: "${HITOCHDIT_DB:?HITOCHDIT_DB saknas i $KONF}"
command -v psql >/dev/null || { echo "Saknar psql – kör: sudo apt install postgresql-client" >&2; exit 1; }

MAPP="${HITOCHDIT_BACKUP:-$HOME/Dokument/Claude/HitochDit/backup}"
BEHALL=60
STAMP="$(date +%Y-%m-%d_%H%M)"
umask 077                                   # bara du kan läsa filerna
mkdir -p "$MAPP"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LOGG="$MAPP/backup.log"
export PGCLIENTENCODING=UTF8 PAGER=cat

# CSV via \copy fungerar oavsett vilken PostgreSQL-version datorn har (pg_dump kräver samma eller nyare version än servern)
psql "$HITOCHDIT_DB" -v ON_ERROR_STOP=1 -q <<SQL
\copy (select * from public.besok order by id) to '$TMP/besok.csv' with (format csv, header true)
\copy (select * from public.profiler order by skapad) to '$TMP/profiler.csv' with (format csv, header true)
\copy (select * from public.meddelanden) to '$TMP/meddelanden.csv' with (format csv, header true)
\copy (select * from public.medaljer order by period, cup, plats) to '$TMP/medaljer.csv' with (format csv, header true)
\copy (select id, email, created_at, last_sign_in_at from auth.users order by created_at) to '$TMP/konton.csv' with (format csv, header true)
SQL

# Antal rader som kontroll (räknas i databasen – meddelanden kan innehålla radbrytningar)
SAMMANFATTNING="$(psql "$HITOCHDIT_DB" -tA -F' ' -c "select 'besök', (select count(*) from public.besok), ', profiler', (select count(*) from public.profiler),
  ', meddelanden', (select count(*) from public.meddelanden), ', medaljer', (select count(*) from public.medaljer), ', konton', (select count(*) from auth.users)" | sed 's/ ,/,/g')"
echo "$STAMP  $SAMMANFATTNING" > "$TMP/LASMIG.txt"
echo "Återställning: se Obsidian, Naturapp - Supabase → Säkerhetskopior." >> "$TMP/LASMIG.txt"

FIL="$MAPP/hitochdit_$STAMP.tar.gz"
tar -czf "$FIL" -C "$TMP" besok.csv profiler.csv meddelanden.csv medaljer.csv konton.csv LASMIG.txt

# Ta bort de äldsta så att bara de senaste $BEHALL finns kvar
ls -1t "$MAPP"/hitochdit_*.tar.gz 2>/dev/null | tail -n +$((BEHALL + 1)) | xargs -r rm -f

echo "$STAMP  OK  $SAMMANFATTNING  $(du -h "$FIL" | cut -f1)" >> "$LOGG"
echo "✓ Säkerhetskopia: $FIL ($SAMMANFATTNING)"
