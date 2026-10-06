# Config Folder

Dieser Ordner enthaelt zentrale Konfigurationen und Utilities.

## Inhalte

- config.sh: zentrale Installations-Flags
- docker-compose.prod.yml: Compose-Datei fuer Release/Deploy
- daemon.json: Docker-Daemon-Konfiguration
- utilities/: Diagnose- und Reparaturskripte

## Kompatibilitaet

Setup-Skripte laden zuerst config/config.sh und fallen bei Bedarf auf den alten Root-Pfad zurueck.
