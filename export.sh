#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

log() { printf '[%s] %s\n' "$(date -u +'%F %T UTC')" "$*"; }

BACKUP_DIR="$HOME/debian_backup"
DEB_DIR="$BACKUP_DIR/debs"
ETC_DIR="$BACKUP_DIR/etc"
HOME_BKP_DIR="$BACKUP_DIR/home"
USR_LOCAL_DIR="$BACKUP_DIR/usr_local"
TMP_DIR="$BACKUP_DIR/tmp"
LOG_FILE="/media/sf_Debian/backup.log"
BACKUP_TAR="/media/sf_Debian/debian_backup.tar.gz"

mkdir -p "$DEB_DIR" "$ETC_DIR" "$HOME_BKP_DIR" "$USR_LOCAL_DIR" "$TMP_DIR"

log "Starte Backup. Ausgabe-Verzeichnis: $BACKUP_DIR"
log "Tar-Ziel: $BACKUP_TAR"
log "Erstelle Liste installierter Pakete..."
PKG_LIST="$TMP_DIR/packages.txt"
# Nur wirklich installierte Pakete
dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' | sort -u > "$PKG_LIST"
cp -f "$PKG_LIST" "$BACKUP_DIR/main_packages.txt"

if have apt-mark; then
  apt-mark showmanual | sort -u > "$BACKUP_DIR/manual_packages.txt" || true
fi

log "Sichere Pakete nach $DEB_DIR ..."
cd "$DEB_DIR"
total_pkgs=$(wc -l < "$PKG_LIST" || echo 0)
idx=0

while read -r pkg; do
  idx=$((idx + 1))
  printf '[%s] (%d/%d) %s\n' "$(date -u +'%F %T UTC')" "$idx" "$total_pkgs" "Bearbeite Paket: $pkg"

  if apt-get download "$pkg" >/dev/null 2>&1; then
    log "  OK: aus Repo geladen: $pkg"
    continue
  fi

  if have dpkg-repack; then
    log "  REPACK: Paket nicht aus Repo verfügbar, repack: $pkg"
    if ! dpkg-repack "$pkg" --output-dir="$DEB_DIR" >/dev/null 2>&1; then
      log "  FEHLER: Repack fehlgeschlagen: $pkg"
    fi
  else
    log "  WARN: Weder Download noch Repack möglich für: $pkg"
  fi
done < "$PKG_LIST"

rsync -aAXH --numeric-ids --info=progress2 \
  --exclude='/fstab' \
  --exclude='/machine-id' \
  --exclude='/network/interfaces/*-save' \
  --exclude='/lightdm/' \
  --exclude='/ssh/' \
  --exclude='/ssh/ssh_host*' \
  /etc/ "$ETC_DIR/"

rsync -aAXH --numeric-ids --info=progress2 /home/ "$HOME_BKP_DIR/"
rsync -aAXH --numeric-ids --info=progress2 /usr/local/ "$USR_LOCAL_DIR/"

tar -C "$BACKUP_DIR" -czf "$BACKUP_TAR" .

log "Backup abgeschlossen!"
log "Pakete in: $DEB_DIR"
log "Konfigurationen in: $ETC_DIR"
log "Benutzerverzeichnisse in: $HOME_BKP_DIR"
log "Weitere lokale Software in: $USR_LOCAL_DIR"
log "Backup bereit zur Wiederherstellung (z. B. Debian 13.1)."
