#!/usr/bin/env bash
# Återställer användardata (profiler, besök, kontaktmeddelanden) från en säkerhetskopia gjord med tools/backup.sh.
#
#   aterstall.sh                      provkör med senaste kopian – visar vad som skulle återställas, ändrar inget
#   aterstall.sh --kor                återställer på riktigt
#   aterstall.sh FIL.tar.gz [--kor]   använd en viss kopia
#   aterstall.sh --epost a@b.se ...   bara en användares data
#
# Bara rader som SAKNAS läggs tillbaka – befintliga rader ändras aldrig (säkert att köra flera gånger).
# Användare kopplas via e-post: har någon fått nytt konto (t.ex. efter ett nytt Supabase-projekt) hamnar
# deras gamla besök på det nya kontot. Användare som inte loggat in i nya projektet hoppas över (listas).
# Kontaktmeddelanden återställs utan att skicka ntfy-aviseringar.
set -euo pipefail
KONF="${HOME}/.config/hitochdit/db.env"
[[ -f "$KONF" ]] || { echo "Saknar $KONF" >&2; exit 1; }
# shellcheck disable=SC1090
source "$KONF"
: "${HITOCHDIT_DB:?HITOCHDIT_DB saknas i $KONF}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MAPP="${HITOCHDIT_BACKUP:-$HOME/Dokument/Claude/HitochDit/backup}"

KOR=0; EPOST=""; FIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kor) KOR=1 ;;
    --epost) EPOST="${2:?ange e-postadress efter --epost}"; shift ;;
    *.tar.gz) FIL="$1" ;;
    *) echo "Okänt argument: $1" >&2; exit 1 ;;
  esac; shift
done
if [[ -z "$FIL" ]]; then
  FIL="$(ls -1t "$MAPP"/hitochdit_*.tar.gz 2>/dev/null | head -n1 || true)"
  [[ -n "$FIL" ]] || { echo "Hittar ingen säkerhetskopia i $MAPP" >&2; exit 1; }
fi
[[ -f "$FIL" ]] || { echo "Hittar inte $FIL" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar -xzf "$FIL" -C "$TMP"
echo "→ Kopia: $(basename "$FIL")"; sed -n 1p "$TMP/LASMIG.txt" | sed 's/^/  innehåller: /'
[[ $KOR -eq 1 ]] && echo "→ Läge: ÅTERSTÄLLER PÅ RIKTIGT" || echo "→ Läge: provkörning (inget sparas) – lägg till --kor för att återställa"
[[ -n "$EPOST" ]] && echo "→ Bara användaren: $EPOST"

# Tillfälliga tabeller med kopians kolumner (som text) – klarar kopior från äldre versioner av databasen
ladda() {  # ladda <namn>
  local f="$TMP/$1.csv"; [[ -f "$f" ]] || return 0
  local kol; kol="$(head -n1 "$f" | tr -d '\r' | sed 's/,/ text, /g') text"
  echo "create temp table s_$1 ($kol);"
  echo "\\copy s_$1 from '$f' with (format csv, header true)"
}
{
  echo "\\set ON_ERROR_STOP on"
  echo "\\pset pager off"
  echo "begin;"
  for t in konton profiler besok meddelanden; do ladda "$t"; done
  echo "\\o /dev/null"
  echo "select set_config('aterstall.epost', '${EPOST//\'/}', true);"
  echo "\\o"
  cat "$REPO/tools/aterstall.sql"
  [[ $KOR -eq 1 ]] && echo "commit;" || echo "rollback;"
} > "$TMP/kor.sql"

export PGCLIENTENCODING=UTF8 PAGER=cat
psql "$HITOCHDIT_DB" -q < "$TMP/kor.sql"
[[ $KOR -eq 1 ]] && echo "✓ Återställt." || echo "ℹ Provkörning klar – inget ändrat. Kör igen med --kor för att återställa."
