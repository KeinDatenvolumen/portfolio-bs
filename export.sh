#!/usr/bin/env bash
set -euo pipefail

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
PKG_INSTALL_TXT="$BACKUP_DIR/packages_install.txt"

# Alle installierten Pakete erfassen
dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' | sort -u > "$PKG_LIST"
cp -f "$PKG_LIST" "$BACKUP_DIR/main_packages.txt"

# Nur manuell installierte Pakete speichern (optional)
apt-mark showmanual | sort -u > "$BACKUP_DIR/manual_packages.txt" || true

cd "$DEB_DIR"
sudo apt update -y
sudo apt upgrade -y
sudo apt autoremove -y

# Listen für unterschiedliche Behandlung vorbereiten
> "$PKG_INSTALL_TXT"
> "$PKG_REPACK"

echo
echo "Prüfe Paketverfügbarkeit (nur trixie-Repos zählen)..."
while read -r pkg; do
  [ -z "$pkg" ] && continue

  list_output=$(apt-cache policy "$pkg" || true)

  # Prüfe, ob das Paket in 'stable' gelistet ist
  if echo "$list_output" | grep -qi 'trixie'; then
    echo "$pkg" >> "$PKG_INSTALL_TXT"
    echo "Repo (trixie): $pkg"
  else
    echo "$pkg" >> "$PKG_REPACK"
    echo "Offline sichern (nicht im trixie Repo): $pkg"
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
rsync -aAXH \
  --exclude='/fstab' \
  --exclude='/machine-id' \
  --exclude='/network/interfaces/*-save' \
  --exclude='/ssh/' \
  --exclude='/ssh/ssh_host*' \
  /etc/ "$ETC_DIR/"

rsync -aAXH /home/ "$HOME_BKP_DIR/"
rsync -aAXH /usr/local/ "$USR_LOCAL_DIR/"

# Archiv erstellen
tar -C "$BACKUP_DIR" -czf "$BACKUP_TAR" .

echo
echo "Backup abgeschlossen:"
echo "  - Pakete aus Repo: $PKG_INSTALL_TXT"
echo "  - Offline-Pakete:  $PKG_REPACK"
echo "  - Archiv:          $BACKUP_TAR"
