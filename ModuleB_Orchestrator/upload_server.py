"""
Snap3D — Flask Mobil Upload Sunucusu (Modül B Eki)
===================================================
Her iOS ve Android cihazın fotoğraflarını kabul eder.
30 fotoğraf tamamlandığında Meshroom → Blender pipeline'ını tetikler.

Kullanım:
    pip install flask
    python upload_server.py [--port 8765] [--config config.json]

Endpoint'ler:
    POST   /upload              → Fotoğraf yükle
    GET    /status/<session_id> → Pipeline durumunu sorgula
    GET    /download/<session_id> → Tamamlanan GLB'yi indir
    GET    /sessions            → Tüm oturumları listele
    DELETE /session/<session_id> → Oturumu sil
"""

import os
import sys
import json
import uuid
import time
import shutil
import logging
import argparse
import threading
import subprocess
import platform
from datetime import datetime
from pathlib import Path

try:
    from flask import Flask, request, jsonify, send_file, abort
except ImportError:
    print("[HATA] Flask kurulu değil.")
    print("Lütfen şunu çalıştırın:  pip install flask")
    sys.exit(1)

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)-8s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("Snap3D.UploadServer")

# ─── Konfigürasyon Yükleyici ──────────────────────────────────────────────────
def load_config(config_path: str) -> dict:
    with open(config_path, encoding="utf-8") as f:
        cfg = json.load(f)
    # _comment anahtarlarını filtrele
    def strip(d):
        return {k: strip(v) if isinstance(v, dict) else v
                for k, v in d.items() if not k.startswith("_")}
    return strip(cfg)

# ─── Oturum Durumu (in-memory) ────────────────────────────────────────────────
# { session_id: { "count": int, "status": str, "glb_path": str | None } }
sessions: dict[str, dict] = {}
sessions_lock = threading.Lock()

STATUS_CAPTURING   = "capturing"
STATUS_PROCESSING  = "processing"
STATUS_MESHING     = "meshing"
STATUS_OPTIMIZING  = "optimizing"
STATUS_DONE        = "done"
STATUS_ERROR       = "error"


# ─── Pipeline ─────────────────────────────────────────────────────────────────
class MobilePipeline:
    def __init__(self, cfg: dict, base_dir: str):
        self.cfg      = cfg
        self.base_dir = base_dir

    def _resolve(self, rel: str) -> str:
        if os.path.isabs(rel): return rel
        return os.path.normpath(os.path.join(self.base_dir, rel))

    def _update_status(self, session_id: str, status: str, glb_path: str | None = None):
        with sessions_lock:
            if session_id in sessions:
                sessions[session_id]["status"] = status
                if glb_path:
                    sessions[session_id]["glb_path"] = glb_path
        log.info(f"[{session_id}] → {status}")

    def run(self, session_id: str, images_dir: str):
        """Meshroom → Blender pipeline'ını arka planda çalıştır."""
        self._update_status(session_id, STATUS_PROCESSING)

        meshroom_cfg = self.cfg["meshroom"]
        blender_cfg  = self.cfg["blender"]

        meshroom_out = os.path.join(self._resolve(meshroom_cfg["output_dir"]), session_id)
        blender_out  = self._resolve(blender_cfg["output_dir"])
        os.makedirs(meshroom_out, exist_ok=True)
        os.makedirs(blender_out,  exist_ok=True)

        # ── Adım 1: Meshroom ──────────────────────────────────────────────────
        try:
            self._update_status(session_id, STATUS_MESHING)
            binary = shutil.which(
                meshroom_cfg.get(
                    "binary_windows" if platform.system() == "Windows" else "binary_linux",
                    "meshroom_batch"
                )
            )
            if not binary:
                raise FileNotFoundError("Meshroom binary bulunamadı.")

            cmd = [binary, "--input", images_dir, "--output", meshroom_out,
                   "--pipeline", meshroom_cfg.get("pipeline", "photogrammetry")]
            log.info(f"[{session_id}] Meshroom: {' '.join(cmd)}")
            subprocess.run(cmd, check=True)

            # OBJ bul
            obj_path = None
            for root, _, files in os.walk(meshroom_out):
                for f in files:
                    if f.lower().endswith(".obj"):
                        obj_path = os.path.join(root, f)
                        break
            if not obj_path:
                raise FileNotFoundError("Meshroom OBJ çıktısı bulunamadı.")

        except Exception as e:
            log.error(f"[{session_id}] Meshroom hatası: {e}")
            self._update_status(session_id, STATUS_ERROR)
            return

        # ── Adım 2: Blender ───────────────────────────────────────────────────
        try:
            self._update_status(session_id, STATUS_OPTIMIZING)
            glb_path = os.path.join(blender_out, f"{session_id}.glb")

            if platform.system() == "Windows":
                runner = self._resolve(blender_cfg["runner_windows"])
            else:
                runner = self._resolve(blender_cfg["runner_unix"])
                os.chmod(runner, 0o755)

            cmd = [
                runner,
                "--input",  obj_path,
                "--output", glb_path,
                "--decimate", str(blender_cfg.get("decimate", 0.1)),
            ]
            log.info(f"[{session_id}] Blender: {' '.join(cmd)}")
            subprocess.run(cmd, check=True)

            if not os.path.isfile(glb_path):
                raise FileNotFoundError(f"GLB üretilemedi: {glb_path}")

            self._update_status(session_id, STATUS_DONE, glb_path)
            log.info(f"[{session_id}] ✓ TAMAMLANDI → {glb_path}")

        except Exception as e:
            log.error(f"[{session_id}] Blender hatası: {e}")
            self._update_status(session_id, STATUS_ERROR)


# ─── Flask Uygulaması ─────────────────────────────────────────────────────────
def create_app(cfg: dict, base_dir: str) -> Flask:
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 50 * 1024 * 1024  # 50 MB/dosya

    capture_cfg = cfg["capture"]
    min_photos  = capture_cfg.get("min_photos", 30)
    allowed_ext = {e.lower().lstrip(".") for e in capture_cfg.get("supported_extensions", [".jpg", ".jpeg", ".png"])}

    captures_root = os.path.normpath(os.path.join(base_dir, capture_cfg["watch_dir"]))
    pipeline = MobilePipeline(cfg, base_dir)

    def _allowed(filename: str) -> bool:
        return "." in filename and filename.rsplit(".", 1)[1].lower() in allowed_ext

    # ── POST /upload ──────────────────────────────────────────────────────────
    @app.route("/upload", methods=["POST"])
    def upload():
        """
        Fotoğraf yükle.
        Form alanları:
            file       → image file (multipart)
            session_id → (opsiyonel) oturum ID; yoksa yeni oluşturulur
        """
        if "file" not in request.files:
            return jsonify({"error": "Dosya bulunamadı (field: 'file')"}), 400

        file = request.files["file"]
        if not file.filename or not _allowed(file.filename):
            return jsonify({"error": "Geçersiz dosya türü. Kabul: " + str(allowed_ext)}), 400

        session_id = request.form.get("session_id") or datetime.now().strftime("%Y%m%d_%H%M%S")

        # Oturumu kayıt altına al
        with sessions_lock:
            if session_id not in sessions:
                sessions[session_id] = {
                    "status":    STATUS_CAPTURING,
                    "count":     0,
                    "glb_path":  None,
                    "created_at": datetime.now().isoformat(),
                }

        # Dosyayı kaydet
        session_dir = os.path.join(captures_root, session_id)
        os.makedirs(session_dir, exist_ok=True)

        safe_name = f"{int(time.time() * 1000)}_{file.filename}"
        save_path = os.path.join(session_dir, safe_name)
        file.save(save_path)

        with sessions_lock:
            sessions[session_id]["count"] += 1
            count = sessions[session_id]["count"]

        log.info(f"[{session_id}] Fotoğraf #{count}: {safe_name}")

        # Yeterli fotoğraf biriktiyse pipeline tetikle
        if count >= min_photos and sessions[session_id]["status"] == STATUS_CAPTURING:
            with sessions_lock:
                sessions[session_id]["status"] = STATUS_PROCESSING

            thread = threading.Thread(
                target=pipeline.run,
                args=(session_id, session_dir),
                daemon=True,
            )
            thread.start()
            log.info(f"[{session_id}] Pipeline tetiklendi ({count}/{min_photos} fotoğraf)")

        return jsonify({
            "session_id":   session_id,
            "photo_count":  count,
            "min_photos":   min_photos,
            "status":       sessions[session_id]["status"],
            "pipeline_started": count >= min_photos,
        }), 200

    # ── GET /status/<session_id> ──────────────────────────────────────────────
    @app.route("/status/<session_id>", methods=["GET"])
    def get_status(session_id):
        """Pipeline ve çekim durumunu sorgula."""
        with sessions_lock:
            session = sessions.get(session_id)

        if not session:
            return jsonify({"error": "Oturum bulunamadı"}), 404

        response = {
            "session_id":  session_id,
            "status":      session["status"],
            "photo_count": session["count"],
            "min_photos":  min_photos,
            "created_at":  session.get("created_at"),
            "glb_ready":   session["status"] == STATUS_DONE,
            "download_url": f"/download/{session_id}" if session["status"] == STATUS_DONE else None,
        }
        return jsonify(response), 200

    # ── GET /download/<session_id> ────────────────────────────────────────────
    @app.route("/download/<session_id>", methods=["GET"])
    def download_glb(session_id):
        """Tamamlanan GLB dosyasını indir."""
        with sessions_lock:
            session = sessions.get(session_id)

        if not session:
            return jsonify({"error": "Oturum bulunamadı"}), 404

        if session["status"] != STATUS_DONE or not session["glb_path"]:
            return jsonify({
                "error": f"GLB henüz hazır değil. Durum: {session['status']}",
                "status": session["status"],
            }), 202   # 202 Accepted — işlem devam ediyor

        glb_path = session["glb_path"]
        if not os.path.isfile(glb_path):
            return jsonify({"error": "GLB dosyası bulunamadı"}), 500

        return send_file(
            glb_path,
            mimetype="model/gltf-binary",
            as_attachment=True,
            download_name=f"snap3d_{session_id}.glb",
        )

    # ── GET /sessions ─────────────────────────────────────────────────────────
    @app.route("/sessions", methods=["GET"])
    def list_sessions():
        """Tüm aktif oturumları listele."""
        with sessions_lock:
            data = [
                {
                    "session_id": sid,
                    "status":     s["status"],
                    "count":      s["count"],
                    "glb_ready":  s["status"] == STATUS_DONE,
                }
                for sid, s in sessions.items()
            ]
        return jsonify({"sessions": data, "total": len(data)}), 200

    # ── DELETE /session/<session_id> ──────────────────────────────────────────
    @app.route("/session/<session_id>", methods=["DELETE"])
    def delete_session(session_id):
        """Oturum verisini sil."""
        with sessions_lock:
            removed = sessions.pop(session_id, None)

        if not removed:
            return jsonify({"error": "Oturum bulunamadı"}), 404

        return jsonify({"message": f"Oturum silindi: {session_id}"}), 200

    # ── GET / (sağlık kontrolü) ───────────────────────────────────────────────
    @app.route("/", methods=["GET"])
    def health():
        return jsonify({
            "service":    "Snap3D Upload Server",
            "status":     "running",
            "min_photos": min_photos,
            "sessions":   len(sessions),
            "endpoints": {
                "upload":   "POST /upload",
                "status":   "GET  /status/<session_id>",
                "download": "GET  /download/<session_id>",
                "sessions": "GET  /sessions",
            }
        }), 200

    return app


# ─── Entry Point ──────────────────────────────────────────────────────────────
def parse_args():
    parser = argparse.ArgumentParser(description="Snap3D Mobile Upload Server")
    parser.add_argument("--port",   "-p", type=int,  default=8765,
                        help="Sunucu portu (varsayılan: 8765)")
    parser.add_argument("--host",         default="0.0.0.0",
                        help="Bağlanılacak IP (0.0.0.0 = tüm ağ arayüzleri)")
    parser.add_argument("--config", "-c",
                        default=os.path.join(os.path.dirname(__file__), "config.json"),
                        help="Config dosyası yolu")
    return parser.parse_args()


def main():
    args   = parse_args()
    cfg    = load_config(args.config)
    app    = create_app(cfg, base_dir=os.path.dirname(os.path.abspath(args.config)))

    log.info("=" * 58)
    log.info("  Snap3D Mobil Upload Sunucusu BAŞLADI")
    log.info(f"  Adres  : http://{args.host}:{args.port}")
    log.info(f"  Yerel  : http://localhost:{args.port}")
    log.info(f"  Upload : POST http://<IP>:{args.port}/upload")
    log.info(f"  Durum  : GET  http://<IP>:{args.port}/status/<id>")
    log.info(f"  İndir  : GET  http://<IP>:{args.port}/download/<id>")
    log.info("=" * 58)

    # Geliştirme modunda debug=False, production için gerekirse gunicorn kullan
    app.run(host=args.host, port=args.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
