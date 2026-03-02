# Modül C: Blender Headless Optimizasyon Motoru

Snap3D pipeline'ının son adımıdır. Meshroom'dan gelen `.obj` dosyasını alır, topolojiyi temizler, poligon sayısını %90 düşürür ve web'e hazır `.glb` dosyası üretir. Tamamıyla komut satırından (headless) çalışır; Blender arayüzüne ihtiyaç duymaz.

---

## Gereksinimler

| Araç | Minimum Sürüm | İndirme |
|------|--------------|---------|
| Blender | 3.6 LTS | https://www.blender.org/download/ |
| Python | 3.10+ | Blender ile birlikte gelir |

> **Not:** `bpy` modülü Blender içinde yerleşik gelir. Pip ile ayrıca kurulum gerekmez.

---

## Kurulum

```powershell
# Windows — Blender'ın PATH'e ekli olup olmadığını kontrol et
where blender
# Yoksa şunu çalıştır (kendi versiyonuna göre yolu değiştir)
$env:PATH += ";C:\Program Files\Blender Foundation\Blender 4.3"
```

```bash
# Linux / macOS
which blender
# Yoksa BLENDER_EXE değişkeni ile belirt
export BLENDER_EXE=/opt/blender/blender
```

---

## Kullanım

### Windows

```bat
cd ModuleC_Blender

REM Temel kullanım
run_blender.bat --input model.obj --output output.glb

REM Özel decimate oranı (0.05 → %95 azalma)
run_blender.bat --input model.obj --output output.glb --decimate 0.05

REM Tüm parametreler
run_blender.bat ^
    --input  C:\scan\shoe.obj ^
    --output C:\scan\shoe_optimized.glb ^
    --decimate 0.1 ^
    --merge-distance 0.0001 ^
    --fill-holes-sides 4096
```

### Linux / macOS

```bash
chmod +x run_blender.sh
./run_blender.sh --input model.obj --output output.glb
./run_blender.sh --input model.obj --output output.glb --decimate 0.05
```

### Doğrudan Blender ile

```bash
blender --background --python blender_optimizer.py -- \
    --input model.obj \
    --output output.glb
```

---

## Parametreler

| Parametre | Varsayılan | Açıklama |
|-----------|-----------|---------|
| `--input` | *zorunlu* | Kaynak `.obj` dosya yolu |
| `--output` | *zorunlu* | Çıktı `.glb` dosya yolu |
| `--decimate` | `0.1` | Polygon tutma oranı (0.1 = %10'unu tut, %90 azal) |
| `--merge-distance` | `0.0001` | Birleştirme mesafesi (metre) |
| `--fill-holes-sides` | `4096` | Kapatılacak maksimum delik kenar sayısı |
| `--max-vertices` | `50000` | Bilgilendirme amaçlı hedef vertex sayısı |

---

## Pipeline Adımları

```
[1] Sahne temizliği      → Boş sahne
[2] OBJ import           → Ham mesh yüklendi
[3] remove_doubles       → Üst üste vertex birleştirildi
[4] Decimate Modifier    → Poligon sayısı %90 azaltıldı
[5] fill_holes           → Açık yüzeyler kapatıldı
[6] Center + Normalize   → (0,0,0)'a taşındı, boyut normalize
[7] GLB export           → Web-ready .glb üretildi
```

---

## Çıktıyı Test Et

Üretilen `.glb` dosyasını şu araçlarla açabilirsin:

- **Tarayıcı:** https://modelviewer.dev/editor/ (sürükle-bırak)
- **Windows:** Varsayılan 3D Viewer uygulaması
- **Online:** https://gltf.report/ (optimizasyon raporu dahil)

---

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| `blender: command not found` | Blender PATH'e ekle veya `BLENDER_EXE` değişkeni ayarla |
| `OBJ dosyası bulunamadı` | `--input` yolunun mutlak yol olduğundan emin ol |
| `Sahnede mesh objesi bulunamadı` | OBJ dosyasının bozuk olmadığını kontrol et |
| Çok fazla polygon kaldı | `--decimate` değerini düşür (örn: `0.05`) |
| Model yanlış boyutta | `center_and_normalize` otomatik çalışır; `--max-vertices` ile kontrol |
