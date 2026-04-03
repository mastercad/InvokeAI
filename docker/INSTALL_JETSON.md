# InvokeAI on NVIDIA Jetson AGX Orin — Docker Installation Guide

**Zielplattform:** Jetson AGX Orin 64 GB · JetPack 6.1 (L4T r36.4) · CUDA 12.6 · aarch64

> Alle Befehle werden vom **Projekt-Root** (`InvokeAI/`) ausgeführt, sofern
> nichts anderes angegeben ist.

---

## Voraussetzungen

| Voraussetzung | Version |
|---|---|
| JetPack SDK | 6.1 (L4T r36.4.0) — auch 6.0 / r36.2.0 funktioniert |
| Docker | ≥ 24 (wird mit JetPack mitgeliefert) |
| nvidia-container-toolkit | aktuell aus JetPack-Repo |
| Git | beliebige aktuelle Version |
| Freier Speicherplatz | mind. 30 GB (Image + Modelle) |

---

## Schritt 1 — Repository klonen

```bash
git clone https://github.com/invoke-ai/InvokeAI.git
cd InvokeAI
# Ab hier: alle Befehle im Projekt-Root (InvokeAI/) ausführen
```

---

## Schritt 2 — nvidia-container-toolkit installieren und konfigurieren

```bash
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Docker auf NVIDIA-Runtime als Standard umstellen und stabilen DNS setzen.
# (systemd-resolved auf Jetson leitet Docker-DNS-Anfragen oft nicht korrekt
#  weiter → "server misbehaving" beim docker pull)
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF

sudo systemctl restart docker
```

### GPU-Zugriff verifizieren

```bash
docker run --rm dustynv/l4t-pytorch:r36.4.0 python3 -c \
  "import torch; print('CUDA verfügbar:', torch.cuda.is_available())"
# Erwartete Ausgabe: CUDA verfügbar: True
```

> Falls `False`: `docker info | grep -i runtime` muss `nvidia` zeigen.

---

## Schritt 3 — Konfiguration anlegen

```bash
# Vorlage kopieren (bleibt im Projekt-Root, Pfad docker/.env)
cp docker/.env.jetson docker/.env

# UID/GID des eigenen Nutzers eintragen (Dateien werden nicht als root erstellt)
echo "CONTAINER_UID=$(id -u)" >> docker/.env
echo "CONTAINER_GID=$(id -g)" >> docker/.env
```

`docker/.env` kann danach mit einem Editor angepasst werden:

| Variable | Bedeutung | Standard |
|---|---|---|
| `HOST_INVOKEAI_ROOT` | Verzeichnis auf dem Jetson für Modelle, Outputs, Datenbank | `~/invokeai` |
| `CONTAINER_INVOKEAI_ROOT` | Gleicher Pfad im Container | `/invokeai` |
| `HF_HOME` | HuggingFace-Modell-Cache (Host) | `~/.cache/huggingface` |
| `INVOKEAI_PORT` | Port der Web-UI | `9090` |
| `CONTAINER_UID` / `CONTAINER_GID` | Nutzer-ID (Rechte der erzeugten Dateien) | `1000` |

---

## Schritt 4 — Image bauen und Container starten

```bash
# Alles in einem Schritt: bauen + starten
docker compose -f docker/docker-compose.jetson.yml up --build -d
```

> **Hinweis:** Der erste Build dauert **15–25 Minuten**, weil `bitsandbytes`
> aus dem Quellcode gegen CUDA 12.6 kompiliert wird. Nachfolgende Builds
> nutzen den Docker-Layer-Cache und sind deutlich schneller.

Logs verfolgen:

```bash
docker compose -f docker/docker-compose.jetson.yml logs -f
```

Die Web-UI ist anschließend unter **http://\<jetson-ip\>:9090** erreichbar.

---

## Alltägliche Befehle

Alle Befehle aus dem **Projekt-Root** (`InvokeAI/`):

```bash
# Stoppen
docker compose -f docker/docker-compose.jetson.yml down

# Starten (ohne Rebuild)
docker compose -f docker/docker-compose.jetson.yml up -d

# Nach Code-Änderungen neu bauen und starten
docker compose -f docker/docker-compose.jetson.yml up --build -d

# Shell im laufenden Container öffnen
docker exec -it invokeai-jetson bash

# CUDA / GPU im Container prüfen
docker exec -it invokeai-jetson python3 -c \
  "import torch; print('CUDA:', torch.cuda.is_available(), '·', torch.cuda.get_device_name(0))"
```

---

## Autostart nach Reboot

Der Container ist mit `restart: unless-stopped` konfiguriert und startet nach
einem Neustart des Jetsons automatisch, sobald der Docker-Daemon läuft.

```bash
sudo systemctl enable docker
```

---

## Dateien auf einen Blick

| Datei | Zweck |
|---|---|
| [Dockerfile_jetson](Dockerfile_jetson) | Multi-Stage Dockerfile (Web-Build · Python-Build · Runtime) |
| [docker-compose.jetson.yml](docker-compose.jetson.yml) | Compose-Konfiguration für Jetson |
| [.env.jetson](.env.jetson) | Vorlage für die `.env`-Konfigurationsdatei |
| [docker-entrypoint.sh](docker-entrypoint.sh) | Container-Einstiegspunkt (UID-Mapping, Verzeichnisse) |

---

## Technische Hintergründe

**Warum `dustynv/l4t-pytorch` als Basis-Image?**
NVIDIA veröffentlicht kein offizielles Jetson-PyTorch-Wheel für PyPI. Das
`dustynv`-Image bringt ein gegen die Jetson-GPU (CUDA 12.6, unified memory)
kompiliertes PyTorch mit. Das Venv im Container wird mit
`--system-site-packages` erstellt, damit pip dieses torch *nicht* durch einen
generischen x86-Build von PyPI ersetzt.

**Warum bitsandbytes aus dem Quellcode?**
Fertige `bitsandbytes`-Wheels auf PyPI sind nur für x86_64 vorhanden. Auf
aarch64/Jetson muss die CUDA-Extension gegen CUDA 12.6 selbst kompiliert
werden (`cmake -DCOMPUTE_BACKEND=cuda`).

**`PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`**
Jetson nutzt unified Memory (GPU und CPU teilen dieselben 64 GB). Der
expandable Allocator verhindert Speicher-Fragmentierung beim Laden großer
Modelle.

---

## Bekannte Einschränkungen

- **xformers** ist auf aarch64 nicht verfügbar und wird nicht installiert.
  InvokeAI funktioniert ohne xformers vollständig — es fehlt lediglich eine
  optionale Optimierung für Attention-Berechnungen.
- **onnxruntime-gpu** ist nicht verfügbar; es wird das CPU-only-Paket
  `onnxruntime` genutzt.
