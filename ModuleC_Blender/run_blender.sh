#!/usr/bin/env bash
# ============================================================
#  Snap3D — Blender Headless Optimizer Runner (Linux / macOS)
# ============================================================
#  Kullanim:
#    chmod +x run_blender.sh
#    ./run_blender.sh --input model.obj --output output.glb
#    ./run_blender.sh --input model.obj --output output.glb --decimate 0.05
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMIZER_SCRIPT="$SCRIPT_DIR/blender_optimizer.py"

# ─── Blender yolunu bul ────────────────────────────────────
find_blender() {
    # 1) Ortam değişkeni varsa kullan
    if [[ -n "${BLENDER_EXE:-}" ]]; then
        echo "$BLENDER_EXE"
        return 0
    fi

    # 2) PATH'te ara
    if command -v blender &>/dev/null; then
        echo "blender"
        return 0
    fi

    # 3) macOS uygulama bundle'ları
    for path in \
        "/Applications/Blender.app/Contents/MacOS/Blender" \
        "$HOME/Applications/Blender.app/Contents/MacOS/Blender"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    # 4) Linux yaygın konumlar
    for path in \
        "/usr/local/blender/blender" \
        "/opt/blender/blender" \
        "$HOME/blender/blender"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

BLENDER_EXE=$(find_blender) || {
    echo "[HATA] Blender bulunamadi!"
    echo "Lutfen Blender'i kurun: https://www.blender.org/download/"
    echo "Ya da BLENDER_EXE ortam degiskenini ayarlayin:"
    echo "  export BLENDER_EXE=/path/to/blender"
    exit 1
}

echo "[Snap3D] Blender bulundu: $BLENDER_EXE"

# ─── Script varlığını kontrol et ──────────────────────────
if [[ ! -f "$OPTIMIZER_SCRIPT" ]]; then
    echo "[HATA] blender_optimizer.py bulunamadi: $OPTIMIZER_SCRIPT"
    exit 1
fi

echo "[Snap3D] Pipeline baslatiliyor..."
echo "[Snap3D] Script   : $OPTIMIZER_SCRIPT"
echo "[Snap3D] Argümanlar: $*"
echo ""

# ─── Blender headless çalıştır ────────────────────────────
"$BLENDER_EXE" --background --python "$OPTIMIZER_SCRIPT" -- "$@"

echo ""
echo "[Snap3D] ================================================"
echo "[Snap3D] Pipeline BASARIYLA tamamlandi!"
echo "[Snap3D] ================================================"
