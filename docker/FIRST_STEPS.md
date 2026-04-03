# InvokeAI Jetson — First Steps nach dem Start

## 1. Container starten

```bash
cd /mnt/data/github/InvokeAI
docker compose -f docker/docker-compose.jetson.yml up -d
```

Logs verfolgen:
```bash
docker compose -f docker/docker-compose.jetson.yml logs -f
```

Bereit wenn in den Logs steht:
```
Running on local URL:  http://0.0.0.0:9091
```

---

## 2. Browser öffnen

```
http://<jetson-ip>:9091
```

Lokal auf dem Jetson: http://localhost:9091

---

## 3. Modelle registrieren

InvokeAI muss Modelle in seiner SQLite-Datenbank registrieren, bevor sie
in der UI auswählbar sind. Das passiert **nicht** automatisch beim ersten Start.

### Option A — Script (empfohlen)

```bash
# Alle Standard-Verzeichnisse scannen (/invokeai/models/sd-1, /sdxl, /flux, …)
./docker/register-models.sh

# Nur ein Unterverzeichnis:
./docker/register-models.sh flux

# Backup-Volume scannen (falls eingebunden):
./docker/register-models.sh /invokeai/models_backup
```

Das Script erkennt bereits registrierte Modelle und überspringt sie.

### Option B — WebUI (Model Manager → Add Model → Scan Folder)

Pfad eingeben: `/invokeai/models/flux` (oder ein anderes Unterverz.)  
Markierung **"In-place"** setzen — Pflicht, sonst verschiebt InvokeAI die Dateien!

---

## ⚠️ WICHTIG: Niemals ohne inplace=true registrieren

InvokeAI's Standard-Install-Verhalten **verschiebt** Modelldateien in
UUID-benannte Unterverzeichnisse unter `models_path`. Für Modelle, die
bereits an ihrem endgültigen Speicherort liegen, muss immer `inplace=true`
(WebUI: "In-place") verwendet werden.

**Was passiert ohne inplace:**  
Die Dateien werden in Pfade wie `/invokeai/models/c2bbde1a-f5db-…/model.safetensors`
bewegt und die originale Verzeichnisstruktur geht verloren.

---

## 4. Verzeichnisstruktur der Modelle

InvokeAI erwartet Modelle in typisierten Unterverzeichnissen:

```
/invokeai/models/
├── sd-1/             # Stable Diffusion 1.x (main, controlnet, ip-adapter, …)
├── sdxl/             # Stable Diffusion XL
├── sdxl-refiner/     # SDXL Refiner
├── flux/             # FLUX Modelle
├── sd-3/             # SD 3.x
└── any/              # Modelltyp-unabhängig (LoRA, Embeddings, …)
```

Neue Modelle einfach in das passende Unterverzeichnis kopieren,
dann `register-models.sh` erneut ausführen.

---

## 5. Neue Modelle hinzufügen

### Via Download aus der UI

Model Manager → Add Model → Search oder Hugging Face URL einfügen.  
InvokeAI lädt direkt in die richtige Verzeichnisstruktur herunter und
registriert automatisch.

### Manuell (z.B. von einer externen Quelle)

1. Datei in das passende Unterverzeichnis kopieren:
   ```bash
   cp mein-modell.safetensors /mnt/data/models/sdxl/main/
   ```
2. Script ausführen:
   ```bash
   ./docker/register-models.sh sdxl
   ```

---

## 6. Container stoppen / neu starten

```bash
# Stoppen:
docker compose -f docker/docker-compose.jetson.yml down

# Neu bauen (nach Dockerfile-Änderungen):
docker build -f docker/Dockerfile_jetson -t invokeai-jetson:latest .

# Dann neu starten:
docker compose -f docker/docker-compose.jetson.yml up -d
```

---

## 7. Volume-Mounts Übersicht

| Host-Pfad | Container-Pfad | Zweck |
|-----------|---------------|-------|
| `~/invokeai` | `/invokeai` | DB, Outputs, Configs |
| `/mnt/data/models` | `/invokeai/models` | Hauptspeicher für Modelle |
| `~/.cache/huggingface` | `/invokeai/.cache/huggingface` | HF-Download-Cache |
| `/mnt/data/home_backup/…/models` | `/invokeai/models_backup` | Backup (read-only) |

---

## 8. Bekannte Probleme

| Problem | Lösung |
|---------|--------|
| Port 9091 statt 9090 belegt | `INVOKEAI_PORT=9091` in `docker-compose.jetson.yml` |
| Modelle sichtbar im Dateisystem, aber nicht in UI | `register-models.sh` ausführen |
| Container startet, InvokeAI aber nicht | `docker logs invokeai-jetson` prüfen |
| CUDA nicht erkannt | Sicherstellen dass `docker info` NVIDIA runtime zeigt: `nvidia-ctk runtime configure --runtime=docker` |

Weitere Hilfe: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) und [INSTALL_JETSON.md](INSTALL_JETSON.md)
