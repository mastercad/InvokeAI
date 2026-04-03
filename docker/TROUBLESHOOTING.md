# fehler:
RuntimeError: CUDA driver error: out of memory
(InvokeAI zeigt "Low VRAM Guide" - Hinweis, obwohl genug RAM frei ist)

# ursache (häufigste Ursache auf Jetson):
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
Jetson L4T-CUDA-Driver unterstützt die CUDA VMM APIs (cuMemCreate/cuMemMap) NICHT,
die expandable_segments benötigt. Dadurch schlägt JEDE CUDA-Allokation fehl —
egal wie viel Speicher frei ist. Diagnose: torch.zeros(1GB, device='cuda') schlägt fehl.
Korrekte Einstellung in docker-compose.jetson.yml:
  PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
(Verhindert Fragmentierung ohne VMM-Abhängigkeit)

# ursache (seltener): falsche/fehlende InvokeAI-Speicherkonfiguration:
# In InvokeAI >=6.x sind INVOKEAI_RAM und INVOKEAI_VRAM DEPRECATED.
# Die neuen Namen sind:
#   INVOKEAI_MAX_CACHE_RAM_GB       (war: INVOKEAI_RAM)
#   INVOKEAI_MAX_CACHE_VRAM_GB      (war: INVOKEAI_VRAM)
# Ohne korrekten Namen ignoriert InvokeAI den Wert und nutzt Heuristiken.
# Korrekter Wert im Log: "Using user-defined RAM cache size: 48.0 GB."
# Falscher Wert im Log: "Calculated model RAM cache size: ... Heuristics applied: [1]"
#
# Wichtige Einstellungen für Jetson UMA (sind bereits in docker-compose.jetson.yml):
#   INVOKEAI_MAX_CACHE_RAM_GB=48
#   INVOKEAI_DEVICE_WORKING_MEM_GB=8    (Default 3 GB — zu wenig für hohe Auflösungen)
#   INVOKEAI_ENABLE_PARTIAL_LOADING=true
#   INVOKEAI_PRECISION=float16
#   PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
#
# loesung: Container neu starten (Env-Vars werden beim Start gelesen)

# ursache B — nvpmodel nicht in MAXN-Modus nach Reboot:
# Prüfen mit: sudo nvpmodel -q
# Expected: "NV Power Mode: MAXN" / "0"

# loesung (nach jedem Reboot einmalig ausführen):
sudo nvpmodel -m 0       # MAXN: alle CPU-Kerne, max GPU-Takt
sudo jetson_clocks       # Alle Clocks auf Maximum setzen

# dauerhaft (systemd-Dienst, einmalig einrichten):
sudo tee /etc/systemd/system/jetson-performance.service <<'EOF'
[Unit]
Description=Jetson MAXN power mode + max clocks
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nvpmodel -m 0
ExecStart=/usr/bin/jetson_clocks
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now jetson-performance.service

# zusätzlich: InvokeAI-Speicher für Jetson UMA konfigurieren
# (ist bereits in docker-compose.jetson.yml gesetzt):
# INVOKEAI_VRAM=0
# INVOKEAI_RAM=48
# INVOKEAI_PRECISION=float16
# Diese drei Variablen beheben den Low-VRAM-Hinweis dauerhaft.

---

# fehler:
double free or corruption (out)
Fatal Python error: Aborted

# loesung:
docker run --rm --runtime=nvidia --gpus all invoke_ai_test:latest rm -rf ~/.nv ~/.torch ~/.cache/pip ~/.cache/torch_extensions

# fehler:
raise RuntimeError(
RuntimeError: Failed to import transformers.models.auto.image_processing_auto because of the following error (look up to see its traceback):
operator torchvision::nms does not exist

# loesung:
torchvision und torch runter hauen und kompatible versionen installieren mit
pip install torch==2.4.0+cu122 torchvision==0.15.1+cu122 --extra-index-url https://pytorch.org/whl/jetson
