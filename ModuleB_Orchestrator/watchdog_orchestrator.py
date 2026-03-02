"""
Snap3D — Python Watchdog Orkestrasyon Modülü (Modül B)
=======================================================
Captures klasörünü izler → 30 fotoğraf tamamlandığında
Meshroom CLI ile 3B mesh üretir → Blender ile optimize eder.

Kullanım:
    pip install -r requirements.txt
    python watchdog_orchestrator.py [--config config.json]

Opsiyonel:
    python watchdog_orchestrator.py --config /path/to/config.json
"""

import os
import sys
import json
import time
import shutil
import logging
import argparse
import platform
import subprocess
import threading
from datetime import datetime
from pathlib import Path

# ─── Watchdog Kütüphanesi ──────────────────────────────────────────────────────
try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler, FileCreatedEvent
except ImportError:
    print("[HATA] watchdog kütüphanesi bulunamadı.")
    print("Lütfen şunu çalıştırın:  pip install -r requirements.txt")
    sys.exit(1)

# ─── İsteğe Bağlı: AWS S3 ──────────────────────────────────────────────────────
try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False


# ═══════════════════════════════════════════════════════════════════════════════
#  Yardımcı: Loglama Kurulumu
# ═══════════════════════════════════════════════════════════════════════════════
def setup_logging(log_file: str, level: str = "INFO") -> logging.Logger:
    log_dir = os.path.dirname(os.path.abspath(log_file))
    os.makedirs(log_dir, exist_ok=True)

    formatter = logging.Formatter(
        fmt="[%(asctime)s] %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    logger = logging.getLogger("Snap3D.Orchestrator")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))

    # Dosyaya yaz
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setFormatter(formatter)
    logger.addHandler(fh)

    # Konsola yaz
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    return logger


# ═══════════════════════════════════════════════════════════════════════════════
#  Konfigürasyon Yükleyici
# ═══════════════════════════════════════════════════════════════════════════════
def load_config(config_path: str) -> dict:
    path = Path(config_path)
    if not path.is_file():
        raise FileNotFoundError(f"Config dosyası bulunamadı: {config_path}")

    with open(path, encoding="utf-8") as f:
        raw = f.read()

    # Yorum satırlarını temizle (_comment anahtarları)
    cfg = json.loads(raw)

    # Tüm parantezi kaldır, yalnızca gerçek anahtarlar kalsın
    def strip_comments(d):
        if isinstance(d, dict):
            return {k: strip_comments(v) for k, v in d.items() if not k.startswith("_")}
        return d

    return strip_comments(cfg)


def resolve_path(base_dir: str, relative: str) -> str:
    """Config'deki göreli yolları mutlak yola çevir."""
    if os.path.isabs(relative):
        return relative
    return os.path.normpath(os.path.join(base_dir, relative))


# ═══════════════════════════════════════════════════════════════════════════════
#  Meshroom Runner
# ═══════════════════════════════════════════════════════════════════════════════
class MeshroomRunner:
    def __init__(self, cfg: dict, logger: logging.Logger):
        self.cfg = cfg["meshroom"]
        self.logger = logger
        self.output_dir = cfg["_resolved"]["meshroom_output"]

    def find_binary(self) -> str:
        """İşletim sistemine göre Meshroom binary'sini bul."""
        sys_platform = platform.system()
        if sys_platform == "Windows":
            key = "binary_windows"
        elif sys_platform == "Darwin":
            key = "binary_macos"
        else:
            key = "binary_linux"

        binary_name = self.cfg.get(key, self.cfg.get("binary", "meshroom_batch"))

        # PATH'te ara
        found = shutil.which(binary_name)
        if found:
            return found

        raise FileNotFoundError(
            f"Meshroom binary bulunamadı: '{binary_name}'\n"
            f"Meshroom'u indirin: https://alicevision.org/#meshroom\n"
            f"Binary'yi PATH'e ekleyin veya config.json'da güncelleyin."
        )

    def run(self, images_dir: str, session_id: str) -> str:
        """
        Meshroom CLI ile photogrammetry pipeline'ını çalıştır.
        Çıktı OBJ dosyasının yolunu döndürür.
        """
        binary = self.find_binary()
        output_path = os.path.join(self.output_dir, session_id)
        os.makedirs(output_path, exist_ok=True)

        cmd = [
            binary,
            "--input", images_dir,
            "--output", output_path,
            "--pipeline", self.cfg.get("pipeline", "photogrammetry"),
        ]
        cmd.extend(self.cfg.get("extra_args", []))

        self.logger.info(f"[MESHROOM] Başlatılıyor: {' '.join(cmd)}")
        self.logger.info(f"[MESHROOM] Çıktı dizini: {output_path}")

        start = time.time()
        result = subprocess.run(
            cmd,
            capture_output=False,
            text=True,
            cwd=output_path,
        )
        elapsed = time.time() - start

        if result.returncode != 0:
            raise RuntimeError(
                f"Meshroom başarısız (exit code {result.returncode}). "
                f"Süre: {elapsed:.0f}s"
            )

        self.logger.info(f"[MESHROOM] Tamamlandı — {elapsed:.0f} saniye")

        # Çıktı OBJ dosyasını bul
        obj_file = self._find_obj(output_path)
        self.logger.info(f"[MESHROOM] OBJ bulundu: {obj_file}")
        return obj_file

    @staticmethod
    def _find_obj(search_dir: str) -> str:
        """Meshroom çıktı dizininde .obj dosyasını özyinelemeli bul."""
        for root, _, files in os.walk(search_dir):
            for f in files:
                if f.lower().endswith(".obj"):
                    return os.path.join(root, f)
        raise FileNotFoundError(
            f"Meshroom çıktısında .obj bulunamadı: {search_dir}\n"
            "Meshroom pipeline'ının başarıyla tamamlandığını kontrol edin."
        )


# ═══════════════════════════════════════════════════════════════════════════════
#  Blender Runner
# ═══════════════════════════════════════════════════════════════════════════════
class BlenderRunner:
    def __init__(self, cfg: dict, logger: logging.Logger):
        self.blender_cfg = cfg["blender"]
        self.logger = logger
        self.output_dir = cfg["_resolved"]["blender_output"]

    def _get_runner(self) -> str:
        """İşletim sistemine göre wrapper script yolunu döndür."""
        if platform.system() == "Windows":
            runner = self.blender_cfg["runner_windows"]
        else:
            runner = self.blender_cfg["runner_unix"]
        return runner

    def run(self, obj_path: str, session_id: str) -> str:
        """
        Blender headless optimizer'ı çalıştır.
        Üretilen GLB dosyasının yolunu döndürür.
        """
        os.makedirs(self.output_dir, exist_ok=True)
        output_glb = os.path.join(self.output_dir, f"{session_id}.glb")

        runner = self._get_runner()
        cmd = [
            runner,
            "--input", obj_path,
            "--output", output_glb,
            "--decimate", str(self.blender_cfg.get("decimate", 0.1)),
            "--merge-distance", str(self.blender_cfg.get("merge_distance", 0.0001)),
            "--fill-holes-sides", str(self.blender_cfg.get("fill_holes_sides", 4096)),
        ]

        # Linux/macOS: script çalıştırma izni ver
        if platform.system() != "Windows":
            os.chmod(runner, 0o755)

        self.logger.info(f"[BLENDER] Başlatılıyor: {' '.join(cmd)}")

        start = time.time()
        result = subprocess.run(cmd, capture_output=False, text=True)
        elapsed = time.time() - start

        if result.returncode != 0:
            raise RuntimeError(
                f"Blender optimizer başarısız (exit code {result.returncode}). "
                f"Süre: {elapsed:.0f}s"
            )

        if not os.path.isfile(output_glb):
            raise FileNotFoundError(
                f"GLB dosyası üretilemedi: {output_glb}"
            )

        size_mb = os.path.getsize(output_glb) / (1024 * 1024)
        self.logger.info(
            f"[BLENDER] GLB üretildi — {output_glb} ({size_mb:.2f} MB) "
            f"[{elapsed:.0f}s]"
        )
        return output_glb


# ═══════════════════════════════════════════════════════════════════════════════
#  S3 Uploader (İsteğe Bağlı)
# ═══════════════════════════════════════════════════════════════════════════════
class S3Uploader:
    def __init__(self, cfg: dict, logger: logging.Logger):
        self.s3_cfg = cfg["s3"]
        self.logger = logger
        self.enabled = self.s3_cfg.get("enabled", False)
        self._client = None

    def _get_client(self):
        if self._client is None:
            if not BOTO3_AVAILABLE:
                raise ImportError("boto3 kurulu değil: pip install boto3")
            session = boto3.Session(profile_name=self.s3_cfg.get("aws_profile", "default"))
            self._client = session.client("s3", region_name=self.s3_cfg.get("region", "eu-central-1"))
        return self._client

    def upload(self, local_path: str, session_id: str) -> str | None:
        if not self.enabled:
            return None

        bucket = self.s3_cfg["bucket"]
        prefix = self.s3_cfg.get("prefix", "models/")
        key = f"{prefix}{session_id}/{os.path.basename(local_path)}"

        try:
            client = self._get_client()
            self.logger.info(f"[S3] Yükleniyor: s3://{bucket}/{key}")
            client.upload_file(
                local_path, bucket, key,
                ExtraArgs={"ContentType": "model/gltf-binary"}
            )
            url = f"https://{bucket}.s3.{self.s3_cfg.get('region', 'eu-central-1')}.amazonaws.com/{key}"
            self.logger.info(f"[S3] Yükleme tamamlandı: {url}")
            return url
        except (ClientError, NoCredentialsError) as e:
            self.logger.error(f"[S3] Yükleme başarısız: {e}")
            return None


# ═══════════════════════════════════════════════════════════════════════════════
#  Ana Pipeline
# ═══════════════════════════════════════════════════════════════════════════════
class PipelineRunner:
    def __init__(self, cfg: dict, logger: logging.Logger):
        self.cfg = cfg
        self.logger = logger
        self.meshroom = MeshroomRunner(cfg, logger)
        self.blender = BlenderRunner(cfg, logger)
        self.s3 = S3Uploader(cfg, logger)
        self._lock = threading.Lock()
        self._running = False

    def run(self, images_dir: str):
        """Tam pipeline: Meshroom → Blender → (S3 upload)."""
        with self._lock:
            if self._running:
                self.logger.warning("[PIPELINE] Zaten çalışıyor, bu istek atlandı.")
                return
            self._running = True

        session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.logger.info("=" * 60)
        self.logger.info(f"[PIPELINE] Oturum başladı: {session_id}")
        self.logger.info(f"[PIPELINE] Görüntü dizini: {images_dir}")
        self.logger.info("=" * 60)

        t_total = time.time()
        try:
            # Adım 1: Meshroom
            obj_path = self.meshroom.run(images_dir, session_id)

            # Adım 2: Blender
            glb_path = self.blender.run(obj_path, session_id)

            # Adım 3: S3 (isteğe bağlı)
            s3_url = self.s3.upload(glb_path, session_id)

            elapsed = time.time() - t_total
            self.logger.info("=" * 60)
            self.logger.info(f"[PIPELINE DONE] Süre: {elapsed:.0f}s")
            self.logger.info(f"[PIPELINE DONE] GLB çıktısı : {glb_path}")
            if s3_url:
                self.logger.info(f"[PIPELINE DONE] S3 URL      : {s3_url}")
            self.logger.info("=" * 60)

        except Exception as e:
            self.logger.error(f"[PIPELINE ERROR] {e}", exc_info=True)
        finally:
            with self._lock:
                self._running = False


# ═══════════════════════════════════════════════════════════════════════════════
#  Watchdog Olay İşleyicisi
# ═══════════════════════════════════════════════════════════════════════════════
class CaptureEventHandler(FileSystemEventHandler):
    def __init__(self, cfg: dict, logger: logging.Logger, pipeline: PipelineRunner):
        super().__init__()
        self.cfg = cfg["capture"]
        self.logger = logger
        self.pipeline = pipeline
        self.watch_dir = cfg["_resolved"]["watch_dir"]
        self.min_photos = self.cfg["min_photos"]
        self.extensions = {ext.lower() for ext in self.cfg["supported_extensions"]}
        self.debounce = self.cfg.get("debounce_seconds", 3)
        self._timer: threading.Timer | None = None

    def _is_image(self, path: str) -> bool:
        return Path(path).suffix.lower() in self.extensions

    def _count_images(self) -> int:
        try:
            return sum(
                1 for f in os.listdir(self.watch_dir)
                if self._is_image(f)
            )
        except OSError:
            return 0

    def on_created(self, event):
        if event.is_directory:
            return
        if not self._is_image(event.src_path):
            return

        count = self._count_images()
        self.logger.info(
            f"[CAPTURE] Yeni fotoğraf: {os.path.basename(event.src_path)} "
            f"({count}/{self.min_photos})"
        )

        if count >= self.min_photos:
            # Debounce: Birden fazla tetik için timer'ı sıfırla
            if self._timer is not None:
                self._timer.cancel()
            self._timer = threading.Timer(
                self.debounce,
                self._trigger_pipeline
            )
            self._timer.start()

    def _trigger_pipeline(self):
        count = self._count_images()
        self.logger.info(
            f"[CAPTURE COMPLETE] {count} fotoğraf tamamlandı! "
            f"Pipeline başlatılıyor..."
        )
        # Fotoğrafları oturuma özel klasöre kopyala
        session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        session_dir = os.path.join(
            os.path.dirname(self.watch_dir),
            "sessions",
            session_id
        )
        self._archive_images(session_dir)
        threading.Thread(
            target=self.pipeline.run,
            args=(session_dir,),
            daemon=True,
        ).start()

    def _archive_images(self, session_dir: str):
        """Fotoğrafları oturum klasörüne taşı."""
        os.makedirs(session_dir, exist_ok=True)
        moved = 0
        for fname in os.listdir(self.watch_dir):
            fpath = os.path.join(self.watch_dir, fname)
            if os.path.isfile(fpath) and self._is_image(fpath):
                shutil.move(fpath, os.path.join(session_dir, fname))
                moved += 1
        self.logger.info(
            f"[ARCHIVE] {moved} fotoğraf oturum klasörüne taşındı: {session_dir}"
        )


# ═══════════════════════════════════════════════════════════════════════════════
#  Entry Point
# ═══════════════════════════════════════════════════════════════════════════════
def parse_args():
    parser = argparse.ArgumentParser(description="Snap3D Watchdog Orchestrator")
    parser.add_argument(
        "--config", "-c",
        default=os.path.join(os.path.dirname(__file__), "config.json"),
        help="Konfigürasyon dosyası yolu (varsayılan: config.json)"
    )
    return parser.parse_args()


def resolve_config_paths(cfg: dict, config_dir: str) -> dict:
    """Config'deki tüm göreli yolları mutlak yola çevir."""
    cfg["_resolved"] = {
        "watch_dir":        resolve_path(config_dir, cfg["capture"]["watch_dir"]),
        "meshroom_output":  resolve_path(config_dir, cfg["meshroom"]["output_dir"]),
        "blender_output":   resolve_path(config_dir, cfg["blender"]["output_dir"]),
        "log_file":         resolve_path(config_dir, cfg["logging"]["log_file"]),
    }
    # Blender runner yolları
    cfg["blender"]["runner_windows"] = resolve_path(config_dir, cfg["blender"]["runner_windows"])
    cfg["blender"]["runner_unix"]    = resolve_path(config_dir, cfg["blender"]["runner_unix"])
    cfg["blender"]["script"]         = resolve_path(config_dir, cfg["blender"]["script"])
    return cfg


def main():
    args = parse_args()
    config_dir = os.path.dirname(os.path.abspath(args.config))

    # Config yükle
    cfg = load_config(args.config)
    cfg = resolve_config_paths(cfg, config_dir)

    # Loglama kur
    logger = setup_logging(cfg["_resolved"]["log_file"], cfg["logging"]["level"])

    logger.info("=" * 60)
    logger.info("Snap3D Watchdog Orchestrator BAŞLADI")
    logger.info(f"  İzlenen dizin : {cfg['_resolved']['watch_dir']}")
    logger.info(f"  Min fotoğraf  : {cfg['capture']['min_photos']}")
    logger.info(f"  Log dosyası   : {cfg['_resolved']['log_file']}")
    logger.info("=" * 60)

    # İzlenecek dizini oluştur
    watch_dir = cfg["_resolved"]["watch_dir"]
    os.makedirs(watch_dir, exist_ok=True)

    # Pipeline ve handler kur
    pipeline = PipelineRunner(cfg, logger)
    handler = CaptureEventHandler(cfg, logger, pipeline)

    observer = Observer()
    observer.schedule(handler, watch_dir, recursive=False)
    observer.start()

    logger.info(f"[WATCH] Klasör izleniyor: {watch_dir}")
    logger.info("[WATCH] Durdurmak için Ctrl+C tuşlayın.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("[WATCH] Durdurma sinyali alındı...")
        observer.stop()

    observer.join()
    logger.info("[WATCH] Watchdog durduruldu.")


if __name__ == "__main__":
    main()
