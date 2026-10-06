# ubuntuSetup – Jetson AGX Thor Setup Guide

**Letzte Aktualisierung:** August 2026  
**Version:** 4.0 (Jetson Release Workflow)

---

## 📖 Inhaltsverzeichnis

1. [Überblick und Systemzweck](#überblick-und-systemzweck)
2. [Der Deployment-Workflow](#der-deployment-workflow)
   - [Schritt 1: Release-Bundle lokal erstellen](#schritt-1-release-bundle-lokal-erstellen)
   - [Schritt 2: Artefaktübertragung auf das Zielsystem](#schritt-2-artefaktübertragung-auf-das-zielsystem)
   - [Schritt 3: Ausführung der Installation](#schritt-3-ausführung-der-installation)
   - [Schritt 4: Post-Installations-Verifikation](#schritt-4-post-installations-verifikation)
3. [Detaillierte Projektstruktur](#detaillierte-projektstruktur)
4. [Troubleshooting und Fehlerbehebung](#troubleshooting-und-fehlerbehebung)

---

## Überblick und Systemzweck

**Zweck:** Dieses Projekt dient der hochgradig automatisierten, reproduzierbaren Einrichtung und tiefgreifenden Netzwerkkonfiguration eines NVIDIA Jetson AGX Thor.
Das Repository nutzt einen sauberen, entkoppelten Release-Workflow, um das Zielsystem von unnötigem Quellcode, Git-Historien und Entwicklungs-Artefakten freizuhalten. Es wird lokal auf dem Entwicklungsrechner ein minimales, eigenständiges Bundle erzeugt, das anschließend auf den Jetson übertragen und dort autark ausgeführt wird.

**Was wird installiert und konfiguriert:**

- **Container-Infrastruktur:** Das Setup richtet Docker, Docker Compose und das NVIDIA Container Toolkit ein. Die Laufzeitumgebung wird zwingend so konfiguriert, dass `nvidia` als Standard-Runtime fungiert.
- **Entwicklungs- und Versionskontrollwerkzeuge:** Essenzielle Tools wie Git, Git LFS sowie Editoren und Browser (VS Code, Chromium) werden automatisch installiert.
- **Fernzugriff und Netzwerkinfrastruktur:** Für den sicheren Zugriff werden OpenSSH, Tailscale und dnsmasq bereitgestellt.
- **Hardware-Integration:** Der proprietäre PEAK CAN Treiber (PCAN) für die industrielle Bus-Kommunikation wird aus den Quellen kompiliert und als Kernelmodul geladen.
- **Erweitertes Routing:** Das Jetson-spezifische Netzwerk-Setup konfiguriert Jumbo Frames, Multi-Ethernet-Uplinks, DHCP-Server-Rollen sowie IP-Forwarding und nftables-NAT für komplexe Topologien.

---

## Der Deployment-Workflow

Der Installationsprozess ist in vier strikt getrennte Phasen unterteilt, um eine maximale Stabilität auf der Zielhardware zu gewährleisten.

### Schritt 1: Release-Bundle lokal erstellen

Um das Zielsystem nicht mit überflüssigen Entwicklungsskripten zu belasten, wird zunächst ein komprimiertes Release-Archiv generiert. Führe auf deinem Entwicklungs-PC (Linux, macOS oder WSL) im Root-Verzeichnis des Repositories das Pack-Skript aus:

```bash
bash release.sh
```

Dieser Befehl führt das Skript `scripts/ops/release.sh` aus, welches einen isolierten Ordnerstruktur-Baum im `dist/`-Verzeichnis anlegt. Anschließend sammelt es gezielt die relevanten Dateien (wie `install.sh`, `setup-jetson-thor.sh` und `healthcheck.sh`) und packt sie in ein versioniertes `.tar.gz`-Archiv.

### Schritt 2: Artefaktübertragung auf das Zielsystem

Sobald das Build-Skript abgeschlossen ist, befindet sich im Ordner `dist/` ein neues Archiv (beispielsweise `jetson-setup-bundle-20260810-091427.tar.gz`). Übertrage dieses Archiv über das Netzwerk auf deinen Jetson AGX Thor. Dies geschieht im Idealfall via SCP (Secure Copy):

```bash
scp dist/jetson-setup-bundle-*.tar.gz jetson@<JETSON_IP>:/home/jetson/
```

### Schritt 3: Ausführung der Installation

Verbinde dich im Anschluss über SSH mit dem Jetson, entpacke das übertragene Archiv und starte den Installationsprozess mit Administratorrechten. Das Skript `install.sh` dient hierbei als sicherer Einstiegspunkt, der Vorabprüfungen des Betriebssystems vornimmt und Protokollierungsfunktionen aktiviert.

```bash
# SSH-Sitzung auf dem Jetson aufbauen:
ssh jetson@<JETSON_IP>

# Archiv entpacken und in das Verzeichnis wechseln:
tar -xzf jetson-setup-bundle-*.tar.gz
cd jetson-setup-bundle

# Den eigentlichen Setup-Prozess initiieren:
sudo bash install.sh
```

### Schritt 4: Post-Installations-Verifikation

Nachdem das Installationsskript erfolgreich durchgelaufen ist, sollte die Integrität des Systems geprüft werden. Das Bundle enthält hierfür ein spezielles Diagnosetool.

```bash
bash healthcheck.sh
```

Dieses Skript verifiziert unter anderem, ob Docker aktiv ist, ob die `nvidia`-Runtime als Standard gesetzt wurde, ob der Hostname korrekt konfiguriert ist und ob das PCAN-Modul fehlerfrei in den Kernel geladen wurde.

---

## Detaillierte Projektstruktur

Die Struktur des Repositories spiegelt die Trennung von Konfiguration, Build-Logik und ausführenden Jetson-Skripten wider.

```text
ubuntuSetup/
├── release.sh                 ← Globaler Wrapper; ruft die Logik zur Erstellung des fertigen Deployment-Bundles auf.
├── config/
│   ├── config.sh              ← Zentrale Konfigurationsparameter für das Setup.
│   ├── daemon.json            ← Konfigurationsdatei für den Docker-Daemon, definiert die NVIDIA-Runtime.
│   ├── docker-compose.prod.yml← Produktive Docker-Compose-Referenz für Deployments.
│   └── README.md              ← Dokumentation der Konfigurationsdateien.
├── scripts/
│   ├── ops/
│   │   └── release.sh         ← Die eigentliche Logik für den Bundle-Build, welche die tar.gz-Datei im dist-Ordner schnürt.
│   └── jetson/
│       ├── install.sh         ← Der sichere Einstiegspunkt auf dem Jetson inklusive Preflight-Checks und Logging.
│       ├── setup-jetson-thor.sh ← Das Haupt-Installationsskript, das alle Abhängigkeiten, Pakete und Hardware-Treiber installiert.
│       ├── healthcheck.sh     ← Post-Installations-Test zur Validierung der Systemgesundheit und aktiven Dienste.
│       ├── start_app.sh       ← Skript zum Starten der grafischen Backend-Anwendung und des Chromium-Browsers im Kiosk-Modus.
│       ├── APP-Start.desktop  ← Desktop-Verknüpfung zur bequemen Ausführung der Anwendungsumgebung.
│       └── APP-Update.desktop ← Desktop-Verknüpfung zum updaten des Docker-Containers.
└── envSetup/
    ├── install_pcan_driver.sh ← Komplexes Installationsskript für den PEAK CAN Hardware-Treiber, das Makefile-Patches für Kernel-Kompatibilität anwendet.
    └── jetson/
        ├── docker-compose.yml ← Spezifische Container-Definitionen für die Jetson-Infrastruktur.
        ├── dockersetup.md     ← Dokumentation zu spezifischen Docker-Befehlen und der NVIDIA-Runtime.
        ├── hostname.sh        ← Skript zur Konfiguration des System-Hostnamens und des mDNS-Avahi-Daemons.
        ├── setupRouting.sh    ← Konfiguriert IP-Forwarding, nftables-NAT, dnsmasq und automatisches WAN-Uplink-Failover.
        ├── thorsetup.md       ← Referenz-Dokumentation für die Netzwerkkonfiguration der verschiedenen Ethernet-Schnittstellen.
        └── thorsetup.sh       ← Weist den Schnittstellen (mgbe0 bis mgbe3) statische IPs, DHCP-Rollen oder Uplink-Eigenschaften zu.
```

---

## Troubleshooting und Fehlerbehebung

Trotz umfangreicher Automatisierung können systembedingte Komplikationen auftreten. Hier sind die häufigsten Problemquellen und deren Lösungen detailliert aufgeschlüsselt.

### Hardware und Treiber: PCAN Treiber lädt nicht

- **Symptomatik:** Das `healthcheck.sh`-Skript meldet einen Fehler beim PCAN-Modul, oder die CAN-Schnittstellen sind nicht verfügbar.
- **Diagnose:** Überprüfe den Kernel-Log via `dmesg | tail -n 50`. Achte auf Fehlermeldungen bezüglich _Invalid Argument_ oder _Symbol Version Mismatch_.
- **Lösung:** Stelle zwingend sicher, dass **Secure Boot im BIOS des Jetson deaktiviert ist**. Bei aktiviertem Secure Boot verweigert der Linux-Kernel strikt das Laden von unsignierten Drittanbieter-Modulen. Sollte das Modul weiterhin fehlschlagen, verifiziere, ob das Patching im Skript `install_pcan_driver.sh` (Setzen von `MODVERSIONS = 0`) korrekt für deinen aktuellen `6.8.x-tegra` Kernel angewandt wurde.

### Berechtigungen: Docker funktioniert nicht ohne sudo

- **Symptomatik:** Der Befehl `docker ps` wirft einen _Permission denied_ Fehler, wenn er ohne `sudo` ausgeführt wird.
- **Diagnose:** Der ausführende Benutzer ist nicht korrekt in die UNIX-Gruppe `docker` eingetragen, oder die Sitzung hat die Gruppenänderungen noch nicht registriert.
- **Lösung:** Führe den Befehl `newgrp docker` im aktuellen Terminal aus, um die Gruppenberechtigungen sofort neu einzulesen. Alternativ kannst du dich aus der grafischen Oberfläche oder der SSH-Sitzung einmal komplett ausloggen und wieder einloggen.

### Container-Laufzeitumgebung: NVIDIA Runtime fehlt

- **Symptomatik:** GPU-beschleunigte Container stürzen ab oder finden die CUDA-Bibliotheken nicht.
- **Diagnose:** Überprüfe die aktive Docker-Konfiguration durch den Befehl `docker info | grep -i "Default Runtime"`. Hier muss zwingend `nvidia` stehen.
- **Lösung:** Falls `runc` anstelle von `nvidia` als Standard gesetzt ist, musst du die Docker-Daemon-Konfiguration anpassen. Führe den Befehl `sudo nvidia-ctk runtime configure --runtime=docker --set-as-default` aus und erzwinge einen Neustart des Docker-Dienstes mittels `sudo systemctl restart docker`.
