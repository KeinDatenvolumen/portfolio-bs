# Dokumentation – Debian‑Backup und Wiederherstellungsskripte (portfolio‑bs)

## Inhaltsverzeichnis
1. [Kurzfassung](#kurzfassung)
2. [Zielsetzung und Einsatzszenario](#zielsetzung-und-einsatzszenario)
3. [Rahmenbedingungen und Annahmen](#rahmenbedingungen-und-annahmen)
4. [Gesamtüberblick des Konzepts](#gesamtüberblick-des-konzepts)
5. [Komponenten und Struktur](#komponenten-und-struktur)
6. [Ablauf: Export (Sicherung)](#ablauf-export-sicherung)
7. [Ablauf: Import (Wiederherstellung)](#ablauf-import-wiederherstellung)
8. [Datenhaltung und Verzeichnisstruktur](#datenhaltung-und-verzeichnisstruktur)
9. [Entscheidungen zu Design und Konfiguration](#entscheidungen-zu-design-und-konfiguration)
10. [Konfiguration und Anpassung](#konfiguration-und-anpassung)
11. [Betrieb, Durchführung und Kontrolle](#betrieb-durchführung-und-kontrolle)
12. [Sicherheit, Datenschutz und Risiken](#sicherheit-datenschutz-und-risiken)
13. [Grenzen und mögliche Erweiterungen](#grenzen-und-mögliche-erweiterungen)
14. [Fazit](#fazit)

---

## Kurzfassung
Dieses Projekt stellt zwei Bash‑Skripte bereit, die eine zielgerichtete Sicherung und Wiederherstellung eines Debian‑Systems ermöglichen. Das Konzept konzentriert sich auf die sichere Migration eines Systems zwischen zwei Installationen, insbesondere im Kontext eines Release‑Wechsels (z. B. von Debian 12 „bookworm“ auf Debian 13 „trixie“). Dabei werden installierte Pakete vollständig erfasst, in zwei Gruppen getrennt (aus Repository verfügbar vs. nicht mehr verfügbar), und die letztere Gruppe als Offline‑Pakete gesichert. Zusätzlich werden zentrale Konfigurationsdateien sowie Nutzer‑ und lokale Softwaredaten gesichert. Die Wiederherstellung stellt diese Daten strukturiert wieder her, installiert die Pakete, stellt Konfigurationen und Benutzerdaten zurück und räumt zusätzliche Pakete auf, um möglichst nah am Ausgangszustand zu bleiben.

Das Design fokussiert auf Nachvollziehbarkeit, geringe Abhängigkeiten und robuste Standardwerkzeuge (apt, dpkg, rsync, tar). Dadurch bleibt das Verfahren auf typischen Debian‑Systemen ohne zusätzliche Software lauffähig. Die Dokumentation beschreibt Konzept, Designentscheidungen und Konfigurationen ausführlich und bietet eine fundierte Grundlage für Nutzung, Anpassung und Weiterentwicklung.

---

## Zielsetzung und Einsatzszenario
Die Hauptzielsetzung ist die möglichst verlustfreie Migration eines bestehenden Debian‑Systems in eine neue Umgebung. Das betrifft insbesondere Systeme, die im Zuge eines Major‑Upgrades neu installiert werden müssen oder für die ein „clean install“ bevorzugt wird, wobei die bisherigen Pakete, Konfigurationen und Nutzerdaten erhalten bleiben sollen. Typische Beispiele:

- Upgrade von Debian 12 auf Debian 13 mit frischer Neuinstallation.
- Migration von einem physischen System in eine virtuelle Maschine.
- Umzug eines Systems in eine neue Umgebung (z. B. andere Festplatte oder Server).
- Wiederherstellung eines Systems nach einem Problem, bei dem die Installation neu aufgesetzt wurde.

Das Verfahren zielt darauf ab, den Ist‑Zustand des Systems so vollständig wie möglich zu erfassen, dabei aber auf ein sicheres Wiederherstellungsmodell zu achten. Kritische Dateien wie System‑IDs, SSH‑Host‑Keys oder Passwortdatenbanken werden nicht automatisch überschrieben, um Konflikte und Sicherheitsprobleme zu vermeiden. Dadurch wird eine Balance zwischen Vollständigkeit und Sicherheit erreicht.

---

## Rahmenbedingungen und Annahmen
Das Projekt trifft folgende Annahmen, die für die korrekte Nutzung relevant sind:

- Das System basiert auf Debian und verwendet den Paketmanager `apt` sowie `dpkg`.
- Der Benutzer besitzt sudo‑Rechte und kann administrative Befehle ausführen.
- Auf dem System ist `rsync` verfügbar.
- Für die Sicherung von Offline‑Paketen ist `dpkg-repack` installiert (oder wird nachinstalliert).
- Es existiert ein Verzeichnis für den Austausch der Archivdatei (Standard: `/media/sf_Debian/`), z. B. ein Shared Folder in VirtualBox.
- Auf dem Zielsystem sind passende Repository‑Quellen eingerichtet (z. B. Debian 13 „trixie“), damit die Paketinstallation aus dem Repository funktionieren kann.

Diese Rahmenbedingungen beeinflussen die Designentscheidungen direkt: Die Skripte sind bewusst so gestaltet, dass sie mit standardisierten Debian‑Werkzeugen arbeiten und keine komplexen Abhängigkeiten erzeugen.

---

## Gesamtüberblick des Konzepts
Das Konzept besteht aus zwei getrennten Schritten und entsprechend zwei Skripten:

1. **Export (Sicherung)**
   - Erfassung aller installierten Pakete.
   - Trennung in Pakete, die im Ziel‑Repository verfügbar sind, und Pakete, die nicht verfügbar sind.
   - Offline‑Sicherung nicht verfügbarer Pakete als `.deb`‑Dateien.
   - Sicherung von Konfigurationen und Nutzerdaten (`/etc`, `/home`, `/usr/local`).
   - Verpackung aller Sicherungsdaten in ein Archiv.

2. **Import (Wiederherstellung)**
   - Entpacken des Archives in eine definierte Restore‑Struktur.
   - Installation der im Repository verfügbaren Pakete.
   - Installation der offline gesicherten Pakete.
   - Wiederherstellung von Konfigurationen und Benutzerdaten.
   - Wiederherstellung manueller Paketmarkierungen.
   - Entfernen zusätzlicher Pakete, die nach der Neuinstallation vorhanden sind, aber nicht zum ursprünglichen System gehörten.

Durch diese Struktur wird ein kontrollierbarer, nachvollziehbarer Prozess gewährleistet. Gleichzeitig werden Risiken reduziert, die bei einem direkten System‑Clone auftreten würden (z. B. ungewollte Überschreibung sensibler Dateien).

---

## Komponenten und Struktur
Das Repository enthält zwei zentrale Skripte:

- `export.sh` – dient der Erfassung, Sicherung und Archivierung.
- `import.sh` – dient der Wiederherstellung und dem Abgleich mit dem ursprünglichen Zustand.

Beide Skripte sind bewusst kurz und transparent gehalten. Sie arbeiten mit gut dokumentierten Standardwerkzeugen, was sowohl Wartbarkeit als auch Fehlerdiagnose erleichtert. Das Fehlen externer Abhängigkeiten reduziert die Komplexität und erhöht die Portabilität.

---

## Ablauf: Export (Sicherung)
Der Exportprozess ist in logisch aufeinanderfolgende Schritte gegliedert:

1. **Vorbereitung des Sicherungsordners**
   - Ein vorhandenes Sicherungsverzeichnis wird entfernt, um eine saubere Ausgangslage zu schaffen.
   - Die Unterordner für Pakete, Konfiguration und Nutzerdaten werden neu erstellt.

2. **Erfassung der Paketliste**
   - Über `dpkg-query` werden alle installierten Pakete ermittelt.
   - Diese Liste wird als Referenz gespeichert (`main_packages.txt`).
   - Zusätzlich wird die Liste der manuell installierten Pakete gespeichert (`manual_packages.txt`).

3. **Systemaktualisierung vor dem Export**
   - `apt update`, `apt upgrade` und `apt autoremove` werden ausgeführt, um einen konsistenten Stand zu sichern und veraltete Pakete zu entfernen.

4. **Paketverfügbarkeit im Ziel‑Repository**
   - Für jedes Paket wird geprüft, ob es im Ziel‑Release verfügbar ist (Standard: „trixie“).
   - Verfügbare Pakete werden in `packages_install.txt` geschrieben.
   - Nicht verfügbare Pakete werden in `packages_repack.txt` gesammelt.

5. **Offline‑Sicherung nicht verfügbarer Pakete**
   - Für jedes nicht verfügbare Paket wird `dpkg-repack` verwendet, um eine `.deb`‑Datei zu erzeugen.
   - Diese `.deb`‑Pakete werden im Sicherungsverzeichnis abgelegt.

6. **Sicherung von Konfigurations‑ und Benutzerdaten**
   - `rsync` wird mit Optionen zur Erhaltung von Rechten, ACLs und erweiterten Attributen verwendet (`-aAXH`).
   - Bestimmte systemkritische Dateien in `/etc` werden bewusst ausgeschlossen (z. B. `machine-id`, SSH‑Host‑Keys).
   - Das vollständige `/home` und `/usr/local` werden gesichert.

7. **Archivierung**
   - Alle Sicherungsdaten werden in ein gzip‑komprimiertes Tar‑Archiv geschrieben.

Dieser Ablauf ist darauf ausgelegt, einen wiederholbaren und sicheren Export zu gewährleisten, ohne unnötige Risiken für das laufende System zu erzeugen.

---

## Ablauf: Import (Wiederherstellung)
Der Importprozess folgt einer strukturierten Wiederherstellung, die Schritt für Schritt die ursprüngliche Systemkonfiguration rekonstruiert:

1. **Validierung des Backups**
   - Das Skript prüft, ob die Archivdatei existiert.
   - Fehlt diese, wird der Prozess abgebrochen, um Teilzustände zu vermeiden.

2. **Entpacken des Archives**
   - Die Daten werden in ein neues Restore‑Verzeichnis extrahiert.
   - Ein eventuell vorhandenes Restore‑Verzeichnis wird vorher entfernt, um Konflikte zu vermeiden.

3. **Installation verfügbarer Repository‑Pakete**
   - Die in `packages_install.txt` gelisteten Pakete werden über `apt install` installiert.
   - Die Pakete werden danach mit `apt-mark auto` markiert, um den ursprünglichen „automatisch installierten“ Status zu rekonstruieren.

4. **Installation offline gesicherter Pakete**
   - Alle `.deb`‑Dateien im Backup werden installiert.
   - Bei Konflikten wird eine Reparaturinstallation (`apt -f install`) durchgeführt.

5. **Wiederherstellung von Konfiguration und Daten**
   - `/etc` wird zurückgespielt, jedoch ohne die kritischen Dateien für Benutzer‑ und Systemidentität.
   - `/home` und `/usr/local` werden vollständig wiederhergestellt.

6. **Wiederherstellung manueller Paketmarkierungen**
   - Pakete, die ursprünglich manuell installiert wurden, werden entsprechend markiert.

7. **Bereinigung zusätzlicher Pakete**
   - Ein Abgleich der aktuellen Pakete mit der ursprünglichen Liste identifiziert zusätzliche Pakete.
   - Diese werden entfernt, damit das System möglichst exakt dem Ausgangszustand entspricht.

Der Importprozess priorisiert Konsistenz und Nachvollziehbarkeit, mit besonderer Aufmerksamkeit für Paket‑Status und Systemidentität.

---

## Datenhaltung und Verzeichnisstruktur
Das Backup erzeugt eine klar strukturierte Verzeichnisstruktur, die sowohl für Wiederherstellung als auch für manuelle Einsicht geeignet ist:

```
<BACKUP_DIR>/
├── debs/                     # Offline gesicherte .deb-Pakete
├── etc/                      # gesicherte Systemkonfiguration
├── home/                     # Benutzerverzeichnisse
├── usr_local/                # lokale Softwareinstallation
├── tmp/                      # temporäre Listen
├── main_packages.txt         # vollständige Paketliste
├── manual_packages.txt       # manuell installierte Pakete
└── packages_install.txt      # aus dem Repository installierbare Pakete
```

Die klare Trennung ermöglicht eine gezielte Wiederherstellung einzelner Bereiche und unterstützt die Analyse bei Problemen. Darüber hinaus ist die Archivierung in einer Datei vorteilhaft für Transfers und Backups über externe Medien.

---

## Entscheidungen zu Design und Konfiguration
Die wichtigsten Design‑ und Konfigurationsentscheidungen sind bewusst auf Einfachheit und Sicherheit ausgerichtet:

1. **Trennung von Export und Import**
   - Durch separate Skripte bleiben Aufgaben klar getrennt.
   - Risiko von Fehlbedienung wird reduziert.

2. **Nutzung etablierter Debian‑Werkzeuge**
   - `apt`, `dpkg`, `dpkg-query` und `rsync` sind Standardwerkzeuge.
   - Dadurch keine zusätzlichen Abhängigkeiten und hohe Kompatibilität.

3. **Filterung nach Ziel‑Release („trixie“)**
   - Eine Migration auf ein neues Release kann Pakete verlieren.
   - Die Verfügbarkeitsprüfung reduziert Fehler bei der Wiederherstellung.

4. **Offline‑Sicherung nicht verfügbarer Pakete**
   - `dpkg-repack` ermöglicht die Sicherung von Paketen, die im Ziel‑Repository fehlen.
   - Dies erlaubt die Wiederherstellung spezieller oder historischer Software.

5. **Ausschlüsse kritischer Dateien**
   - Dateien wie `machine-id` und SSH‑Host‑Keys bleiben unangetastet.
   - Dadurch werden Identitätskonflikte, Netzwerkprobleme und Sicherheitsrisiken vermieden.

6. **Verwendung von `rsync -aAXH`**
   - Dateirechte, ACLs und erweiterte Attribute bleiben erhalten.
   - Besonders relevant für System‑ und Benutzerdateien.

7. **Archivierung in einem einzelnen Tarball**
   - Erleichtert Transfer und Lagerung.
   - Verhindert vergessene Einzeldateien.

8. **Bereinigung zusätzlicher Pakete nach Import**
   - Das Zielsystem wird auf den Ursprung zurückgeführt.
   - System bleibt schlank und konsistent.

Diese Entscheidungen unterstützen ein transparentes und reproduzierbares Vorgehen und reflektieren die Anforderungen an Zuverlässigkeit und Sicherheit bei Systemmigrationen.

---

## Konfiguration und Anpassung
Die Skripte sind über Variablen am Anfang leicht konfigurierbar. Die wichtigsten Parameter sind:

- `BACKUP_DIR` – Basispfad für alle Sicherungsdaten.
- `BACKUP_TAR` – Pfad zur Archivdatei (z. B. Shared Folder).
- `RESTORE_DIR` – Zielordner für entpackte Sicherung.
- `DEB_DIR`, `ETC_DIR`, `HOME_BKP_DIR`, `USR_LOCAL_DIR` – Unterverzeichnisse für Inhalte.

**Anpassungsbeispiele:**

- **Speicherort des Archivs:**
  Ein anderer Speicherort kann genutzt werden, wenn kein Shared Folder verfügbar ist, z. B. eine externe Festplatte oder ein Netzlaufwerk.

- **Ziel‑Release:**
  Die aktuelle Implementierung prüft auf „trixie“. Für andere Release‑Ziele kann dieser String angepasst werden.

- **Ausschlusslisten:**
  In `export.sh` kann die Liste der ausgeschlossenen Dateien in `/etc` erweitert werden, wenn weitere sensible Dateien nicht übertragen werden sollen.

- **Scope der Datensicherung:**
  Sollte `home` oder `usr/local` nicht übertragen werden, können diese Schritte im Skript deaktiviert werden.

Alle Konfigurationsänderungen sollten vor dem ersten Einsatz getestet werden, um unerwartete Nebenwirkungen zu vermeiden.

---

## Betrieb, Durchführung und Kontrolle
Ein typischer Ablauf im Betrieb sieht wie folgt aus:

1. **Export auf dem Quellsystem**
   - Skript `export.sh` ausführen.
   - Ergebnis: Archivdatei im definierten Zielverzeichnis.

2. **Transfer**
   - Archivdatei auf das Zielsystem übertragen (Shared Folder, USB‑Stick, Netzwerk).

3. **Import auf dem Zielsystem**
   - Skript `import.sh` ausführen.
   - Ergebnis: Systemrekonstruktion mit Paketen, Konfiguration und Daten.

4. **Kontrolle**
   - Prüfen, ob zentrale Dienste laufen.
   - Verifizieren, ob Nutzerdateien vorhanden sind.
   - Überprüfen der Paketliste und eventueller Abweichungen.

Für den produktiven Einsatz empfiehlt sich ein zusätzlicher manueller Validierungsschritt, insbesondere bei Systemdiensten, sicherheitsrelevanten Konfigurationen oder spezifischen Anwendungen.

---

## Sicherheit, Datenschutz und Risiken
Da die Skripte mit Root‑Rechten arbeiten und sensible Daten sichern, sind folgende Aspekte zu beachten:

- **Zugriffsrechte:** Das Backup enthält potenziell vertrauliche Daten aus `/home` und `/etc`. Es muss geschützt gespeichert und übertragen werden.
- **SSH‑Schlüssel:** Die Host‑Keys werden nicht wiederhergestellt, um Konflikte zu vermeiden. Benutzer‑SSH‑Schlüssel in `/home` werden jedoch übertragen.
- **Passwortdateien:** Systemdateien wie `/etc/shadow` werden bewusst ausgeschlossen, um Sicherheitsprobleme zu verhindern.
- **Datenintegrität:** Das Archiv sollte vor der Wiederherstellung verifiziert werden (z. B. Prüfsumme).
- **Sudo‑Befehle:** Die Skripte setzen voraus, dass der Benutzer korrekt mit sudo arbeitet. Eine falsche Bedienung kann das System beeinträchtigen.

Die Entscheidung, bestimmte Dateien nicht zu übertragen, dient der Sicherheit. Gleichzeitig kann dies nach der Wiederherstellung manuelle Anpassungen erfordern (z. B. Benutzer‑ oder Gruppen‑Konfiguration).

---

## Grenzen und mögliche Erweiterungen
Die aktuelle Lösung ist bewusst minimalistisch gehalten, wodurch einige Grenzen bestehen:

- Keine automatische Validierung der Repositories.
- Keine integrierte Prüfsummen‑Überprüfung.
- Keine differenzielle Sicherung (nur Voll‑Backup).
- Keine Unterstützung für alternative Paketmanager.
- Keine Protokollierung in Logdateien (nur Standardausgabe).

Mögliche Erweiterungen könnten sein:

- **Checksum‑Generierung und Validierung** für das Backup‑Archiv.
- **Konfigurierbare Ziel‑Releases** über Parameter oder eine Konfigurationsdatei.
- **Logging** mit detaillierten Protokollen zur Fehleranalyse.
- **Dry‑Run‑Modus** zur Simulation des Imports.
- **Integration in System‑Upgrade‑Workflows**, um den Prozess noch automatisierter zu gestalten.

Diese Erweiterungen würden die Robustheit erhöhen, erhöhen aber auch die Komplexität. Das aktuelle Design priorisiert Transparenz und einfache Wartbarkeit.

---

## Fazit
Die vorliegenden Skripte liefern eine strukturierte und transparente Methode, ein Debian‑System in eine neue Umgebung zu migrieren. Durch die Trennung in Export und Import, die klare Paketklassifikation sowie die sichere Wiederherstellung von Konfiguration und Nutzerdaten wird ein reproduzierbarer Prozess geschaffen. Die Designentscheidungen – von der Nutzung etablierter Werkzeuge bis zur selektiven Wiederherstellung kritischer Dateien – sorgen für ein ausgewogenes Verhältnis zwischen Vollständigkeit und Sicherheit.

Damit eignet sich das Projekt sowohl als praktisches Werkzeug für Systemmigrationen als auch als Grundlage für weiterführende Automatisierung. Die Dokumentation zeigt, dass die Architektur bewusst auf Verständlichkeit, Anpassbarkeit und geringe Abhängigkeiten ausgerichtet ist, was das System in unterschiedlichen Umgebungen einsetzbar macht.
