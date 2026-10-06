#!/usr/bin/env bash
# Installerar en daglig automatisk säkerhetskopia (systemd-timer för din användare – inget sudo behövs).
# Persistent=true: var datorn avstängd vid körtiden körs kopian strax efter nästa start.
# Kör en gång:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/backup_installera.sh
# Ta bort:      systemctl --user disable --now hitochdit-backup.timer
set -euo pipefail
SKRIPT="$(cd "$(dirname "$0")" && pwd)/backup.sh"
DIR="$HOME/.config/systemd/user"
mkdir -p "$DIR"

cat > "$DIR/hitochdit-backup.service" <<UNIT
[Unit]
Description=Hit och Dit – säkerhetskopia av användardata i Supabase
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $SKRIPT
UNIT

cat > "$DIR/hitochdit-backup.timer" <<UNIT
[Unit]
Description=Hit och Dit – daglig säkerhetskopia

[Timer]
OnCalendar=*-*-* 12:17
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now hitochdit-backup.timer
echo "✓ Daglig säkerhetskopia installerad. Nästa körning:"
systemctl --user list-timers hitochdit-backup.timer --no-pager
