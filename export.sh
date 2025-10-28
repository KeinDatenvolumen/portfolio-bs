#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

BACKUP_DIR="$HOME/debian_backup"
DEB_DIR="$BACKUP_DIR/debs"
ETC_DIR="$BACKUP_DIR/etc"
HOME_BKP_DIR="$BACKUP_DIR/home"
USR_LOCAL_DIR="$BACKUP_DIR/usr_local"
TMP_DIR="$BACKUP_DIR/tmp"
BACKUP_TAR="/media/sf_Debian/debian_backup.tar.gz"

mkdir -p "$DEB_DIR" "$ETC_DIR" "$HOME_BKP_DIR" "$USR_LOCAL_DIR" "$TMP_DIR"

PKG_LIST="$TMP_DIR/packages.txt"

dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' | sort -u > "$PKG_LIST"
cp -f "$PKG_LIST" "$BACKUP_DIR/main_packages.txt"

apt-mark showmanual | sort -u > "$BACKUP_DIR/manual_packages.txt" || true

cd "$DEB_DIR"

while read -r pkg; do
  if apt-get download "$pkg" >/dev/null 2>&1; then
    printf "OK: aus Repo geladen: $pkg"
    continue
  fi

  printf "REPACK: Paket nicht aus Repo verfügbar, repack: $pkg"
  if ! dpkg-repack "$pkg" --output-dir="$DEB_DIR" >/dev/null 2>&1; then
    printf "FEHLER: Repack fehlgeschlagen: $pkg"
  fi
done < "$PKG_LIST"

rsync -aAXH --numeric-ids \
  --exclude='/fstab' \
  --exclude='/machine-id' \
  --exclude='/network/interfaces/*-save' \
  --exclude='/lightdm/' \
  --exclude='/ssh/' \
  --exclude='/ssh/ssh_host*' \
  /etc/ "$ETC_DIR/"

rsync -aAXH --numeric-ids /home/ "$HOME_BKP_DIR/"
rsync -aAXH --numeric-ids /usr/local/ "$USR_LOCAL_DIR/"

tar -C "$BACKUP_DIR" -czf "$BACKUP_TAR" .
