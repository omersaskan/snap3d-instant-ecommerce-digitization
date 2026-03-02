# Modül B: Python Watchdog Orkestrasyon

`captures/` klasörünü gerçek zamanlı izler. 30 fotoğraf tamamlandığında otomatik olarak Meshroom → Blender pipeline'ını başlatır ve isteğe bağlı olarak üretilen `.glb` dosyasını S3'e yükler.

---

## Gereksinimler

| Araç | Minimum Sürüm |
|------|--------------|
| Python | 3.10+ |
| Meshroom | 2023.3+ |
| Blender | 3.6 LTS |

```powershell
# Bağımlılıkları kur
pip install -r requirements.txt
```

---

## Kurulum

### 1. config.json Düzenle

```json
{
  "capture": {
    "watch_dir": "../captures",     // Unity'nin fotoğraf kaydettiği klasör
    "min_photos": 30                // Pipeline tetikleme eşiği
  },
  "meshroom": {
    "binary_windows": "meshroom_batch.exe"  // Meshroom PATH'te olmalı
  },
  "blender": {
    "decimate": 0.1                 // 0.1 → %90 polygon azalma
  },
  "s3": {
    "enabled": false               // S3 yüklemek için true yap
  }
}
```

### 2. PATH Ayarları

```powershell
# Meshroom'u PATH'e ekle (Windows)
$env:PATH += ";C:\Program Files\Meshroom-2023.3"

# Blender zaten ModuleC_Blender/run_blender.bat üzerinden çalışır
```

---

## Çalıştırma

```powershell
# Varsayılan config ile başlat
python watchdog_orchestrator.py

# Özel config dosyası
python watchdog_orchestrator.py --config /path/to/config.json
```

---

## Pipeline Akışı

```
[WATCH]   captures/ klasörü izleniyor
[CAPTURE] Yeni fotoğraf: img_001.jpg (1/30)
[CAPTURE] Yeni fotoğraf: img_030.jpg (30/30)
          ↓ 3 saniyelik debounce
[ARCHIVE] 30 fotoğraf → sessions/20240101_120000/ taşındı
          ↓ Thread'de paralel çalışır
[MESHROOM STARTED] meshroom_batch çalışıyor...
[MESHROOM]          ~45 dakika sonra tamamlanır
[BLENDER STARTED]  blender_optimizer.py çalışıyor...
[PIPELINE DONE]    output_models/20240101_120000.glb üretildi
```

---

## Klasör Yapısı (çalışma zamanında)

```
Snap3D/
├── captures/              ← Unity burada fotoğraf bırakır (izlenen)
├── sessions/
│   └── 20240101_120000/   ← Oturum fotoğrafları
│       ├── img_001.jpg
│       └── ...
├── meshroom_output/
│   └── 20240101_120000/   ← Meshroom çıktısı (OBJ)
├── output_models/
│   └── 20240101_120000.glb ← Son ürün
└── logs/
    └── pipeline.log        ← Tüm loglar
```

---

## S3 Yükle (İsteğe Bağlı)

```json
"s3": {
  "enabled": true,
  "bucket": "snap3d-models",
  "region": "eu-central-1",
  "aws_profile": "default"
}
```

```powershell
# AWS kimlik bilgilerini ayarla
aws configure --profile default
```

---

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| `meshroom_batch: command not found` | PATH'e ekle ve yeniden başlat |
| Pipeline iki kez tetiklendi | `debounce_seconds` değerini artır |
| S3 `NoCredentialsError` | `aws configure` çalıştır |
| Log dosyası açılamadı | `logs/` dizini yoksa oluştur |
