"""
Snap3D — Blender Headless Optimizasyon Motoru (Modül C)
========================================================
Kullanım:
    blender --background --python blender_optimizer.py -- \
        --input path/to/model.obj \
        --output path/to/output.glb \
        [--decimate 0.1] \
        [--max-vertices 50000]

Gereksinimler:
    - Blender 3.6+ (bpy dahil)
    - Komut satırından headless çalışır, GUI gerektirmez.
"""

import sys
import os
import time
import logging
import argparse

# ─── Logging Ayarları ──────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("Snap3D.Blender")


# ─── Argüman Ayrıştırıcı ──────────────────────────────────────────────────────
def parse_args():
    """Blender'ın kendi argümanları arasından bizimkileri ayırt et."""
    # Blender '--' ile kendi argümanlarını kullanıcı argümanlarından ayırır
    try:
        idx = sys.argv.index("--")
        argv = sys.argv[idx + 1:]
    except ValueError:
        argv = []

    parser = argparse.ArgumentParser(
        description="Snap3D: OBJ → optimized GLB pipeline"
    )
    parser.add_argument(
        "--input", "-i",
        required=True,
        help="Kaynak .obj dosyasının tam yolu"
    )
    parser.add_argument(
        "--output", "-o",
        required=True,
        help="Hedef .glb dosyasının tam yolu"
    )
    parser.add_argument(
        "--decimate",
        type=float,
        default=0.1,
        help="Decimate oranı (0.0-1.0). Varsayılan: 0.1 → %90 azalma"
    )
    parser.add_argument(
        "--max-vertices",
        type=int,
        default=50000,
        help="Hedef maksimum vertex sayısı (sadece bilgilendirme amaçlı)"
    )
    parser.add_argument(
        "--merge-distance",
        type=float,
        default=0.0001,
        help="remove_doubles birleştirme mesafesi (metre). Varsayılan: 0.0001"
    )
    parser.add_argument(
        "--fill-holes-sides",
        type=int,
        default=4096,
        help="fill_holes için maximum kenar sayısı. Varsayılan: 4096"
    )
    return parser.parse_args(argv)


# ─── Yardımcı Fonksiyonlar ────────────────────────────────────────────────────
def clear_scene(bpy):
    """Varsayılan Cube, Light ve Camera dahil tüm sahneyi temizle."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    log.info("Sahne temizlendi.")


def import_obj(bpy, filepath: str):
    """OBJ dosyasını sahneye import et; oluşan mesh objesini döndür."""
    if not os.path.isfile(filepath):
        raise FileNotFoundError(f"OBJ dosyası bulunamadı: {filepath}")

    log.info(f"OBJ import ediliyor: {filepath}")
    bpy.ops.wm.obj_import(filepath=filepath)

    # Import sonrası aktif objeyi al
    obj = bpy.context.active_object
    if obj is None or obj.type != "MESH":
        # Bazen import sonrası aktif obje set edilmez; mesh olanı bul
        for o in bpy.context.scene.objects:
            if o.type == "MESH":
                obj = o
                bpy.context.view_layer.objects.active = o
                break

    if obj is None:
        raise RuntimeError("OBJ import başarısız: Sahnede mesh objesi bulunamadı.")

    vert_count = len(obj.data.vertices)
    poly_count = len(obj.data.polygons)
    log.info(f"Import tamamlandı → '{obj.name}' | {vert_count:,} vertex | {poly_count:,} polygon")
    return obj


def select_only(bpy, obj):
    """Yalnızca verilen objeyi seç ve aktif yap."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def remove_doubles(bpy, obj, merge_distance: float = 0.0001):
    """
    Üst üste binen (duplicate) vertexleri birleştir.
    Eski API: remove_doubles → Yeni API (Blender 4+): merge_by_distance
    """
    select_only(bpy, obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")

    # Blender sürümüne göre uyumlu API seç
    blender_version = bpy.app.version  # tuple, örn: (3, 6, 0)
    if blender_version >= (4, 0, 0):
        bpy.ops.mesh.merge_by_distance(threshold=merge_distance)
        log.info(f"merge_by_distance uygulandı (threshold={merge_distance})")
    else:
        bpy.ops.mesh.remove_doubles(threshold=merge_distance)
        log.info(f"remove_doubles uygulandı (threshold={merge_distance})")

    bpy.ops.object.mode_set(mode="OBJECT")


def apply_decimate(bpy, obj, ratio: float = 0.1):
    """
    Decimate Modifier ile poligon sayısını azalt.
    ratio=0.1 → %90 azalma (1M poly → 100K poly).
    """
    select_only(bpy, obj)
    mod = obj.modifiers.new(name="Snap3D_Decimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.001, min(1.0, ratio))   # 0.001 – 1.0 aralığında tut
    mod.use_collapse_triangulate = False

    before = len(obj.data.polygons)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    after = len(obj.data.polygons)

    log.info(
        f"Decimate tamamlandı → {before:,} → {after:,} polygon "
        f"(%{(1 - after / max(before, 1)) * 100:.1f} azalma)"
    )


def fill_holes(bpy, obj, sides: int = 4096):
    """
    Tarama hataları veya açık kenarlardan oluşan delikleri kapat.
    """
    select_only(bpy, obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.fill_holes(sides=sides)
    bpy.ops.object.mode_set(mode="OBJECT")
    log.info(f"fill_holes uygulandı (max_sides={sides})")


def center_and_normalize(bpy, obj):
    """
    Modeli geometri merkezine göre origin ayarla,
    dünya orijinine taşı (0, 0, 0) ve en büyük boyutunu 1 birime normalize et.
    """
    select_only(bpy, obj)

    # Origin'i geometri merkezine taşı
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")

    # Objeyi dünya orijinine taşı
    obj.location = (0.0, 0.0, 0.0)

    # Boyutu normalize et (en büyük eksen = 1 birim)
    dims = obj.dimensions
    max_dim = max(dims.x, dims.y, dims.z)
    if max_dim > 0:
        scale = 1.0 / max_dim
        obj.scale = (scale, scale, scale)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        log.info(
            f"Merkeze alındı ve normalize edildi → boyut: "
            f"({dims.x * scale:.3f}, {dims.y * scale:.3f}, {dims.z * scale:.3f})"
        )
    else:
        log.warning("Boyut sıfır, ölçeklendirme atlandı.")


def export_glb(bpy, filepath: str):
    """
    Tüm sahneyi (mesh + tekstürler) tek .glb dosyası olarak export et.
    """
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_colors=True,
        export_cameras=False,
        export_lights=False,
    )
    size_mb = os.path.getsize(filepath) / (1024 * 1024)
    log.info(f"GLB export tamamlandı → {filepath} ({size_mb:.2f} MB)")


# ─── Ana Pipeline ─────────────────────────────────────────────────────────────
def run_pipeline(args):
    """
    Tam optimizasyon pipeline'ını çalıştır.
    import_obj → remove_doubles → decimate → fill_holes → center → export_glb
    """
    try:
        import bpy
    except ImportError:
        log.error("bpy modülü bulunamadı. Bu scripti Blender içinde çalıştırın:")
        log.error("  blender --background --python blender_optimizer.py -- --input foo.obj --output bar.glb")
        sys.exit(1)

    t_start = time.time()
    log.info("=" * 60)
    log.info("Snap3D Blender Optimizasyon Pipeline BAŞLADI")
    log.info(f"  Giriş : {args.input}")
    log.info(f"  Çıkış : {args.output}")
    log.info(f"  Decimate oranı  : {args.decimate} (hedef %{(1 - args.decimate) * 100:.0f} azalma)")
    log.info(f"  Merge mesafesi  : {args.merge_distance}")
    log.info(f"  Fill holes kenar: {args.fill_holes_sides}")
    log.info("=" * 60)

    # Adım 0: Sahneyi temizle
    clear_scene(bpy)

    # Adım 1: OBJ import
    obj = import_obj(bpy, args.input)

    # Adım 2: Duplicate vertexleri kaldır
    remove_doubles(bpy, obj, merge_distance=args.merge_distance)

    # Adım 3: Decimate (polygon azaltma)
    apply_decimate(bpy, obj, ratio=args.decimate)

    # Adım 4: Delikleri kapat
    fill_holes(bpy, obj, sides=args.fill_holes_sides)

    # Adım 5: Merkeze al ve normalize et
    center_and_normalize(bpy, obj)

    # Adım 6: GLB export
    export_glb(bpy, args.output)

    elapsed = time.time() - t_start
    log.info("=" * 60)
    log.info(f"Pipeline TAMAMLANDI — {elapsed:.1f} saniyede bitti.")
    log.info("=" * 60)


# ─── Entry Point ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    args = parse_args()
    run_pipeline(args)
