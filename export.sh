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
PKG_REPACK="$TMP_DIR/packages_repack.txt"

# Alle installierten Pakete erfassen
dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' | sort -u > "$PKG_LIST"
cp -f "$PKG_LIST" "$BACKUP_DIR/main_packages.txt"

# Nur manuell installierte Pakete speichern (optional)
apt-mark showmanual | sort -u > "$BACKUP_DIR/manual_packages.txt" || true

cd "$DEB_DIR"

# Listen für unterschiedliche Behandlung vorbereiten
> "$PKG_REPACK"
PKG_INSTALL_TXT="$BACKUP_DIR/packages_install.txt"
> "$PKG_INSTALL_TXT"

echo "Prüfe Paketquellen..."
while read -r pkg; do
  # Prüfen, ob das Paket noch in einer Quelle vorhanden ist
  if apt-cache madison "$pkg" | grep -q .; then
    echo "$pkg" >> "$PKG_INSTALL_TXT"
    echo "Repo: $pkg"
  else
    echo "$pkg" >> "$PKG_REPACK"
    echo "Offline sichern (repack): $pkg"
  fi
done < "$PKG_LIST"

echo
echo "Lade/verpacke nicht verfügbare Pakete..."

# Nur die Pakete repacken, die keine Quelle mehr haben
while read -r pkg; do
  [ -z "$pkg" ] && continue
  echo "→ Repack: $pkg"
  if ! dpkg-repack "$pkg" --output-dir="$DEB_DIR" >/dev/null 2>&1; then
    echo "FEHLER: Repack fehlgeschlagen: $pkg"
  fi
done < "$PKG_REPACK"

echo
echo "Starte Dateisicherungen..."

# Konfigurations- und Benutzerdaten sichern
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

# Archiv erstellen
tar -C "$BACKUP_DIR" -czf "$BACKUP_TAR" .

echo
echo "Backup abgeschlossen:"
echo "  - Pakete aus Repo: $PKG_INSTALL_TXT"
echo "  - Offline-Pakete:  $PKG_REPACK"
echo "  - Archiv:          $BACKUP_TAR"
