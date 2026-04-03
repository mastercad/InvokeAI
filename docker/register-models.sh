#!/usr/bin/env bash
# ==============================================================================
# register-models.sh — InvokeAI Jetson: Modelle aus dem models-Verzeichnis
# in die InvokeAI-Datenbank importieren.
#
# WICHTIG: Dieses Script verwendet inplace=true, d.h. die Dateien werden
# NICHT verschoben oder kopiert. InvokeAI registriert die Pfade direkt.
#
# Verwendung:
#   ./docker/register-models.sh [SCAN_DIR ...]
#
# Beispiele:
#   # Alle Standard-InvokeAI-Verzeichnisse scannen (Standard):
#   ./docker/register-models.sh
#
#   # Nur FLUX-Modelle scannen:
#   ./docker/register-models.sh flux
#
#   # Ein zusätzliches Verzeichnis scannen (read-only gemountet):
#   ./docker/register-models.sh /invokeai/models_backup
#
# Voraussetzung: Container muss laufen (docker compose ... up -d)
# ==============================================================================
set -euo pipefail

CONTAINER="${INVOKEAI_CONTAINER:-invokeai-jetson}"
PORT="${INVOKEAI_PORT:-9091}"
BASE_URL="http://localhost:${PORT}/api/v2/models"

# Standard-Verzeichnisse wenn keine Argumente übergeben
DEFAULT_DIRS=(sd-1 sdxl sdxl-refiner flux sd-3 any)

# Prüfe ob Container läuft
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "FEHLER: Container '${CONTAINER}' läuft nicht."
    echo "Starten mit: docker compose -f docker/docker-compose.jetson.yml up -d"
    exit 1
fi

# Prüfe ob API erreichbar ist
if ! docker exec "${CONTAINER}" curl -sf "${BASE_URL}/" > /dev/null 2>&1; then
    echo "FEHLER: InvokeAI API nicht erreichbar auf Port ${PORT}."
    echo "Warte bis der Container vollständig gestartet ist und versuche es erneut."
    exit 1
fi

# Scan-Verzeichnisse bestimmen
if [[ $# -gt 0 ]]; then
    # Argumente als absolute oder relative Pfade behandeln
    SCAN_PATHS=()
    for arg in "$@"; do
        if [[ "$arg" == /* ]]; then
            SCAN_PATHS+=("$arg")
        else
            SCAN_PATHS+=("/invokeai/models/${arg}")
        fi
    done
else
    # Standard: alle InvokeAI-Subdirectories
    SCAN_PATHS=()
    for d in "${DEFAULT_DIRS[@]}"; do
        SCAN_PATHS+=("/invokeai/models/${d}")
    done
fi

TOTAL_SUBMITTED=0
TOTAL_FAILED=0

for scan_path in "${SCAN_PATHS[@]}"; do
    echo ""
    echo "── Scanne: ${scan_path}"

    # Prüfe ob Verzeichnis im Container existiert
    if ! docker exec "${CONTAINER}" test -d "${scan_path}" 2>/dev/null; then
        echo "   ÜBERSPRUNGEN: Verzeichnis existiert nicht im Container."
        continue
    fi

    # Scan über API
    result=$(docker exec "${CONTAINER}" \
        curl -sf "${BASE_URL}/scan_folder?scan_path=${scan_path}" 2>/dev/null \
        || echo '{"detail":"scan failed"}')

    # Fehler prüfen
    if echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if isinstance(d,list) else 1)" 2>/dev/null; then
        :
    else
        msg=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('detail','?'))" 2>/dev/null || echo "Unbekannter Fehler")
        echo "   FEHLER: ${msg}"
        continue
    fi

    # Nicht-installierte Modelle filtern und importieren
    submitted=$(docker exec "${CONTAINER}" bash -c "
        echo '$result' | python3 -c \"
import json, sys, urllib.request, urllib.parse, urllib.error

data = json.load(sys.stdin)
not_installed = [m['path'] for m in data if not m.get('is_installed', False)]
ok = 0; fail = 0

for path in not_installed:
    params = urllib.parse.urlencode({'source': path, 'inplace': 'true'})
    req = urllib.request.Request(
        'http://localhost:${PORT}/api/v2/models/install?' + params,
        data=b'{}',
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        ok += 1
    except Exception as e:
        fail += 1
        print('FAIL:', path, str(e), file=sys.stderr)

print(f'{ok} neu importiert, {fail} Fehler, {len(data) - len(not_installed)} bereits vorhanden')
\"
    " 2>&1)

    echo "   ${submitted}"
    TOTAL_SUBMITTED=$((TOTAL_SUBMITTED + 1))
done

echo ""
echo "══ Fertig. Warte ca. 30 Sekunden bis InvokeAI alle Modelle gehashed hat."
echo "   Dann im Browser Model Manager öffnen und Generierung starten."
echo ""

# Optional: Warten bis alle Jobs abgeschlossen
echo -n "Warte auf Abschluss der Import-Jobs"
for i in $(seq 1 12); do
    sleep 5
    pending=$(docker exec "${CONTAINER}" \
        curl -sf "http://localhost:${PORT}/api/v2/models/install" 2>/dev/null \
        | python3 -c "import json,sys; jobs=json.load(sys.stdin); print(len([j for j in jobs if j.get('status') in ('waiting','running')]))" \
        2>/dev/null || echo "?")
    echo -n "."
    [[ "$pending" == "0" ]] && break
done
echo ""

# Abschlusszählung
total=$(docker exec "${CONTAINER}" \
    curl -sf "http://localhost:${PORT}/api/v2/models/" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('models', d.get('items', []))))" \
    2>/dev/null || echo "?")

echo "✓ ${total} Modelle total in InvokeAI registriert."
