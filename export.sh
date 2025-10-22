#!/usr/bin/env bash
# backup_debian_appliance.sh
# Erstellt ein Replikat einer alten Debian Appliance inkl. Pakete und Konfigurationen
# Optimiert: robustere Fehlerbehandlung, Fortschritt, Checksums, bessere Metadatenwahrung

set -Eeuo pipefail
IFS=$'\n\t'

# --------- Utils ----------
log() { printf '[%s] %s\n' "$(date -u +'%F %T UTC')" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --------- Konfiguration ----------
BACKUP_DIR="$HOME/debian_backup"
DEB_DIR="$BACKUP_DIR/debs"
ETC_DIR="$BACKUP_DIR/etc"
HOME_BKP_DIR="$BACKUP_DIR/home"
USR_LOCAL_DIR="$BACKUP_DIR/usr_local"
TMP_DIR="$BACKUP_DIR/tmp"
LOG_FILE="/media/sf_Debian/backup.log"
BACKUP_TAR="/media/sf_Debian/debian_backup.tar.gz"

mkdir -p "$DEB_DIR" "$ETC_DIR" "$HOME_BKP_DIR" "$USR_LOCAL_DIR" "$TMP_DIR"
# Optionales Logfile (kein Abbruch, falls tee fehlt)
if have tee; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

# --------- Vorab-Info ----------
log "Starte Backup. Ausgabe-Verzeichnis: $BACKUP_DIR"
log "Tar-Ziel: $BACKUP_TAR"

# --------- Schritt 0: Voraussetzungen (nur Hinweise) ----------
for cmd in rsync dpkg-query apt-get tar gzip; do
  if ! have "$cmd"; then
    log "WARN: '$cmd' nicht gefunden. Bitte installieren."
  fi
done
if ! have dpkg-repack; then
  log "HINWEIS: 'dpkg-repack' nicht gefunden. Fallback bei nicht aus Repo verfügbaren Paketen entfällt."
fi

# --------- Schritt 1: Paketlisten sichern ----------
log "Erstelle Liste installierter Pakete..."
PKG_LIST="$TMP_DIR/packages.txt"
# Nur wirklich installierte Pakete
dpkg-query -W -f='${Package} ${Status}\n' | awk '/install ok installed/{print $1}' | sort -u > "$PKG_LIST"
cp -f "$PKG_LIST" "$BACKUP_DIR/main_packages.txt"

# Manuell installierte Pakete (Top-Level) sichern
if have apt-mark; then
  apt-mark showmanual | sort -u > "$BACKUP_DIR/manual_packages.txt" || true
fi

# Debconf-Auswahl (falls vorhanden)
if have debconf-get-selections; then
  debconf-get-selections > "$BACKUP_DIR/debconf_selections.txt" || true
fi

# --------- Schritt 2: Pakete sichern (Download/ Repack) ----------
log "Sichere Pakete nach $DEB_DIR ..."
cd "$DEB_DIR"
total_pkgs=$(wc -l < "$PKG_LIST" || echo 0)
idx=0

# apt-get download legt in das aktuelle Verzeichnis ab
while read -r pkg; do
  idx=$((idx + 1))
  printf '[%s] (%d/%d) %s\n' "$(date -u +'%F %T UTC')" "$idx" "$total_pkgs" "Bearbeite Paket: $pkg"

  # Erst versuchen, aus Repo zu laden
  if apt-get download "$pkg" >/dev/null 2>&1; then
    log "  OK: aus Repo geladen: $pkg"
    continue
  fi

  # Fallback: dpkg-repack, falls vorhanden
  if have dpkg-repack; then
    log "  REPACK: Paket nicht aus Repo verfügbar, repack: $pkg"
    if ! dpkg-repack "$pkg" --output-dir="$DEB_DIR" >/dev/null 2>&1; then
      log "  FEHLER: Repack fehlgeschlagen: $pkg"
    fi
  else
    log "  WARN: Weder Download noch Repack möglich für: $pkg"
  fi
done < "$PKG_LIST"

# Prüfsummen der .deb-Dateien (optional, falls viele Debs kann das dauern)
if have sha256sum; then
  find "$DEB_DIR" -type f -name '*.deb' -print0 | sort -z | xargs -0 sha256sum > "$DEB_DIR/SHA256SUMS" || true
fi

# --------- Schritt 3: /etc sichern ----------
log "Sichere /etc Konfigurationen..."
# Excludes beibehalten wie bei dir
rsync -aAXH --numeric-ids --info=progress2 \
  --exclude='/fstab' \
  --exclude='/machine-id' \
  --exclude='/network/interfaces/*-save' \
  --exclude='/lightdm/' \
  --exclude='/ssh/' \
  --exclude='/ssh/ssh_host*' \
  /etc/ "$ETC_DIR/"

# --------- Schritt 4: /home sichern ----------
log "Sichere /home Verzeichnisse..."
rsync -aAXH --numeric-ids --info=progress2 /home/ "$HOME_BKP_DIR/"

# --------- Schritt 5: /usr/local sichern ----------
log "Sichere /usr/local..."
rsync -aAXH --numeric-ids --info=progress2 /usr/local/ "$USR_LOCAL_DIR/"

# --------- Schritt 6: Archiv erstellen (mit Fortschritt, paralleler Kompression falls möglich) ----------
log "Erstelle tar-Archiv: $BACKUP_TAR"
size_bytes=$(du -sb "$BACKUP_DIR" | awk '{print $1}')

# Wahl der Kompression
COMPRESSOR="gzip -c"
if have pigz; then
  # pigz nutzt alle Kerne
  COMPRESSOR="pigz -c"
fi

# Fortschritt via pv falls verfügbar
if have pv; then
  # Stream-Tar mit pv
  tar -C "$BACKUP_DIR" -cf - . \
    | pv -s "$size_bytes" \
    | eval "$COMPRESSOR" > "$BACKUP_TAR"
else
  # Fallback auf klassisches tar.gz
  tar -C "$BACKUP_DIR" -czf "$BACKUP_TAR" .
fi

# --------- Schritt 7: Checksum des Archivs ----------
if have sha256sum; then
  sha256sum "$BACKUP_TAR" | tee "$BACKUP_TAR.sha256" >/dev/null
  log "SHA256 für Archiv geschrieben nach: $BACKUP_TAR.sha256"
fi

# --------- Zusammenfassung ----------
log "Backup abgeschlossen!"
log "Pakete in: $DEB_DIR"
log "Konfigurationen in: $ETC_DIR"
log "Benutzerverzeichnisse in: $HOME_BKP_DIR"
log "Weitere lokale Software in: $USR_LOCAL_DIR"
log "Backup bereit zur Wiederherstellung (z. B. Debian 13.1)."