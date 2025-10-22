#!/usr/bin/env bash
# restore_debian_appliance.sh
# Stellt ein Backup einer Debian Appliance inkl. Pakete und Konfigurationen wieder her
# Optimiert: robustere Fehlerbehandlung, Fortschritt, Checksum-Prüfung, bessere Metadatenwahrung

set -Eeuo pipefail
IFS=$'\n\t'

if [ ! -d /backup ]; then
  mkdir -p /backup
fi

log() { printf '[%s] %s\n' "$(date -u +'%F %T UTC')" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --------- Konfiguration ----------
BACKUP_TAR="/media/sf_Debian/debian_backup.tar.gz"
BACKUP_SHA="$BACKUP_TAR.sha256"
RESTORE_DIR="/backup/debian_restore"

# --------- Checks ----------
if [ ! -f "$BACKUP_TAR" ]; then
  echo "Backup-Datei $BACKUP_TAR existiert nicht!"
  exit 1
fi

# --------- Schritt 1: Checksum prüfen (falls vorhanden) ----------
if [ -f "$BACKUP_SHA" ] && have sha256sum; then
  log "Prüfe SHA256 des Archivs..."
  # sha256sum -c erwartet 'sha datei', passt
  if ! sha256sum -c "$BACKUP_SHA"; then
    echo "Checksum-Validierung fehlgeschlagen! Abbruch."
    exit 1
  fi
  log "Checksum OK."
else
  log "Keine SHA256-Datei gefunden oder sha256sum fehlt. Überspringe Check."
fi

# --------- Schritt 2: Backup entpacken ----------
mkdir -p "$RESTORE_DIR"
log "Entpacke Backup nach $RESTORE_DIR..."
if have pv; then
  pv "$BACKUP_TAR" | tar -xz -C "$RESTORE_DIR"
else
  tar -xzf "$BACKUP_TAR" -C "$RESTORE_DIR"
fi

DEB_DIR="$RESTORE_DIR/debs"
ETC_DIR="$RESTORE_DIR/etc"
HOME_DIR="$RESTORE_DIR/home"
USR_LOCAL_DIR="$RESTORE_DIR/usr_local"

# --------- Schritt 3: Pakete wieder installieren ----------
log "Installiere gesicherte Pakete..."
shopt -s nullglob
if [ -d "$DEB_DIR" ]; then
  debs=( "$DEB_DIR"/*.deb )
  if (( ${#debs[@]} )); then
    # Einmalige Installation, löst Abhängigkeiten besser
    if ! sudo apt-get install -y --allow-downgrades "${debs[@]}"; then
      log "Fehler bei Installation; versuche fehlende Abhängigkeiten zu lösen..."
      sudo apt-get -f install -y --allow-downgrades
      sudo apt-get install -y --allow-downgrades "${debs[@]}" || log "WARN: Einige Pakete konnten evtl. nicht installiert werden."
    fi
  else
    log "Keine .deb-Dateien im Backup gefunden."
  fi
fi
shopt -u nullglob

# --------- Schritt 4: /etc wiederherstellen ----------
if [ -d "$ETC_DIR" ]; then
  log "Stelle /etc wieder her..."
  sudo rsync -aAXH --numeric-ids --info=progress2 "$ETC_DIR/" /etc/
fi

# --------- Schritt 5: /home wiederherstellen ----------
if [ -d "$HOME_DIR" ]; then
  log "Stelle /home wieder her..."
  sudo rsync -aAXH --numeric-ids --info=progress2 "$HOME_DIR/" /home/
fi

# --------- Schritt 6: /usr/local wiederherstellen ----------
if [ -d "$USR_LOCAL_DIR" ]; then
  log "Stelle /usr/local wieder her..."
  sudo rsync -aAXH --numeric-ids --info=progress2 "$USR_LOCAL_DIR/" /usr/local/
fi

# --------- Schritt 7: Manuelle Pakete (optional) ----------
if [ -f "$RESTORE_DIR/manual_packages.txt" ] && have apt-mark; then
  log "Setze 'manual' Markierungen für Pakete..."
  xargs -r -a "$RESTORE_DIR/manual_packages.txt" sudo apt-mark manual || true
fi

# --------- Schritt 8: Überschüssige Pakete entfernen (Diff) ----------
# Erzeuge aktuelle Paketliste und vergleiche mit main_packages.txt aus dem Backup
if have tee; then
  dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' \
    | sed 's/:.*$//' | sort -u | sudo tee /media/sf_Debian/local_packages.txt >/dev/null
else
  dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' \
    | sed 's/:.*$//' | sort -u > /media/sf_Debian/local_packages.txt
fi

if [ -f "/media/sf_Debian/local_packages.txt" ] && [ -f "$RESTORE_DIR/main_packages.txt" ]; then
  sort -u "$RESTORE_DIR/main_packages.txt" > "$RESTORE_DIR/main_packages.sorted.txt"
  comm -23 /media/sf_Debian/local_packages.txt "$RESTORE_DIR/main_packages.sorted.txt" \
    | sudo tee /media/sf_Debian/to_remove.txt >/dev/null

  log "Pakete, die entfernt werden (nur wenn vorhanden):"
  wc -l /media/sf_Debian/to_remove.txt || true

  # Entferne überzählige Pakete
  xargs -r -a /media/sf_Debian/to_remove.txt sudo apt-get purge -y
  sudo apt-get autoremove -y --purge
fi

# --------- Zusammenfassung ----------
log "Restore abgeschlossen! Pakete, Konfigurationen und Benutzerverzeichnisse wurden wiederhergestellt."