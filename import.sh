#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BACKUP_TAR="/media/sf_Debian/debian_backup.tar.gz"
RESTORE_DIR="/backup/debian_restore"

if [ ! -f "$BACKUP_TAR" ]; then
  echo "Backup-Datei $BACKUP_TAR existiert nicht!"
  exit 1
fi

mkdir -p "$RESTORE_DIR"
echo "Entpacke Backup nach $RESTORE_DIR..."
tar -xzf "$BACKUP_TAR" -C "$RESTORE_DIR"

DEB_DIR="$RESTORE_DIR/debs"
ETC_DIR="$RESTORE_DIR/etc"
HOME_DIR="$RESTORE_DIR/home"
USR_LOCAL_DIR="$RESTORE_DIR/usr_local"

echo "Installiere gesicherte Pakete..."
shopt -s nullglob
if [ -d "$DEB_DIR" ]; then
  debs=( "$DEB_DIR"/*.deb )
  if (( ${#debs[@]} )); then
    if ! sudo apt-get install -y --allow-downgrades "${debs[@]}"; then
      echo "Fehler bei Installation; versuche fehlende Abhängigkeiten zu lösen..."
      sudo apt-get -f install -y --allow-downgrades
      sudo apt-get install -y --allow-downgrades "${debs[@]}" || echo "WARN: Einige Pakete konnten evtl. nicht installiert werden."
    fi
  else
    echo "Keine .deb-Dateien im Backup gefunden."
  fi
fi
shopt -u nullglob

if [ -d "$ETC_DIR" ]; then
  echo "Stelle /etc wieder her..."
  sudo rsync -aAXH --info=progress2 \
	--exclude='passwd' \
	--exclude='group' \
	--exclude='shadow' \
	--exclude='gshadow' \
	"$ETC_DIR/" /etc/
fi

if [ -d "$HOME_DIR" ]; then
  echo "Stelle /home wieder her..."
  sudo rsync -aAXH --info=progress2 "$HOME_DIR/" /home/
fi

if [ -d "$USR_LOCAL_DIR" ]; then
  echo "Stelle /usr/local wieder her..."
  sudo rsync -aAXH --info=progress2 "$USR_LOCAL_DIR/" /usr/local/
fi

if [ -f "$RESTORE_DIR/manual_packages.txt" ]; then
  echo "Setze 'manual' Markierungen für Pakete..."
  xargs -r -a "$RESTORE_DIR/manual_packages.txt" sudo apt-mark manual || true
fi

dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' \
    | sed 's/:.*$//' | sort -u | sudo tee /media/sf_Debian/local_packages.txt >/dev/null

if [ -f "/media/sf_Debian/local_packages.txt" ] && [ -f "$RESTORE_DIR/main_packages.txt" ]; then
  sort -u "$RESTORE_DIR/main_packages.txt" > "$RESTORE_DIR/main_packages.sorted.txt"
  comm -23 /media/sf_Debian/local_packages.txt "$RESTORE_DIR/main_packages.sorted.txt" \
    | sudo tee /media/sf_Debian/to_remove.txt >/dev/null

  echo "Pakete, die entfernt werden (nur wenn vorhanden):"
  wc -l /media/sf_Debian/to_remove.txt || true
  
  xargs -r -a /media/sf_Debian/to_remove.txt sudo apt-get purge -y
  sudo apt-get autoremove -y --purge
fi
