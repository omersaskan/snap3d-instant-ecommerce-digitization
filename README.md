# Snap3D: Instant E-Commerce Digitization

**Fiziksel ürünleri profesyonel ekipman olmadan, yalnızca telefonla 3B/AR formatına dönüştüren uçtan uca pipeline.**

KOBİ satıcılar, Snap3D mobil uygulamasıyla çektikleri fotoğrafları GLB modeline dönüştürür ve web sitelerine AR destekli embed kodu ekler.

---

## Mimari Şema

```
┌───────────────────────────────────────────────────────────────┐
│                    SNAP3D PİPELİNE                            │
│                                                               │
│   📱 TELEFON          🖥️  SUNUCU           🌍 WEB              │
│                                                               │
│  ┌──────────┐       ┌──────────┐       ┌──────────────┐      │
│  │  Modül A │──────▶│  Modül B │──────▶│   Modül C    │      │
│  │  Unity   │WiFi / │  Python  │Subprocess│  Blender  │      │
│  │ AR Dome  │  S3   │ Watchdog │       │ Headless     │      │
│  └──────────┘       └──────────┘       └──────┬───────┘      │
│  • 30 fotoğraf      • Klasör izle             │ .glb          │
│  • 15° başına 1     • Meshroom tetikle        ▼               │
│  • Auto-capture     • Blender tetikle  ┌──────────────┐      │
│                     • S3 yükle         │   Viewer     │      │
│                                        │  model-viewer│      │
│                                        └──────────────┘      │
└───────────────────────────────────────────────────────────────┘
```

| Katman | Teknoloji | Görevi |
|--------|-----------|--------|
| **Frontend** | Unity C# + AR Foundation | AR Dome rehberlik, otomatik çekim |
| **Data Layer** | Local Storage / AWS S3 | Fotoğraf ve metadata saklama |
| **Engine** | Meshroom CLI | Fotoğraftan 3B Mesh üretimi |
| **Post-Process** | Blender headless (bpy) | Topoloji temizliği + GLB export |
| **Viewer** | `<model-viewer>` | 3B modeli web'de AR ile sergileme |

---

## Klasör Yapısı

```
Snap3D Instant E-Commerce Digitization/
│
├── 📁 ModuleA_Unity/               ← Unity AR yakalama arayüzü
│   └── Assets/Scripts/
│       ├── DomeCaptureManager.cs   ← AR Dome + otomatik çekim
│       ├── CaptureProgressUI.cs    ← Yeşil nokta UI, progress bar
│       └── FileUploadManager.cs    ← HTTP / S3 yükleyici
│   └── README_unity.md
│
├── 📁 ModuleB_Orchestrator/        ← Python orkestrasyon
│   ├── watchdog_orchestrator.py    ← Watchdog + Meshroom + Blender
│   ├── config.json                 ← Tüm yapılandırma
│   ├── requirements.txt
│   └── README_orchestrator.md
│
├── 📁 ModuleC_Blender/             ← Blender headless optimizer
│   ├── blender_optimizer.py        ← OBJ → temizle → GLB
│   ├── run_blender.bat             ← Windows wrapper
│   ├── run_blender.sh              ← Linux/macOS wrapper
│   └── README_blender.md
│
├── 📁 viewer/                      ← Web görüntüleyici
│   ├── index.html                  ← Tam özellikli viewer
│   └── embed.html                  ← Satıcı embed snippet
│
└── README.md                       ← Bu dosya
```

---

## Hızlı Başlangıç

### 1. Blender Optimizer (test için)

```powershell
# Elinizdeki herhangi bir OBJ ile test edin
cd ModuleC_Blender
run_blender.bat --input test.obj --output test_optimized.glb
```

### 2. Python Watchdog

```powershell
cd ModuleB_Orchestrator
pip install -r requirements.txt

# config.json içinde Meshroom/Blender yollarını güncelleyin
python watchdog_orchestrator.py
```

### 3. Unity AR

1. Unity 2022 LTS + AR Foundation 5.x kurun
2. `ModuleA_Unity/Assets/Scripts/` içindeki `.cs` dosyalarını projenize ekleyin
3. `README_unity.md` kurulum adımlarını takip edin

### 4. Web Viewer

```powershell
# Tarayıcıda açın — GLB dosyasını sürükleyin
start viewer/index.html

# Veya doğrudan modele yönlendirin
# viewer/embed.html?model=https://your-s3-bucket.s3.amazonaws.com/model.glb
```

---

## Detaylı Dokümantasyon

| Modül | README |
|-------|--------|
| Unity AR | [ModuleA_Unity/README_unity.md](ModuleA_Unity/README_unity.md) |
| Python Watchdog | [ModuleB_Orchestrator/README_orchestrator.md](ModuleB_Orchestrator/README_orchestrator.md) |
| Blender Optimizer | [ModuleC_Blender/README_blender.md](ModuleC_Blender/README_blender.md) |

---

## Geliştirme Sırası (Önerilen)

1. **Modül C** — Elimizdeki bir OBJ ile Blender scriptini test et
2. **Modül B** — Watchdog + Meshroom pipeline'ını entegre et  
3. **Modül A** — Unity projesini oluştur ve sahneyi kur

---

*Snap3D — KOBİ'ler için 3B e-ticaret çözümü*
