# Modül A (iOS Native): Apple Object Capture ile On-Device 3D Tarama

iPhone 12 Pro veya üzeri cihazlarda **Apple'ın `ObjectCaptureSession` API'si** kullanılarak nesne doğrudan cihaz üzerinde 3B modele dönüştürülür. Sunucu, Meshroom veya harici işleme gerekmez.

---

## Nasıl Çalışır?

```
[Kullanıcı]      → Nesneyi masaya koyar
[ObjectCaptureView] → AR bounding box ve yön kılavuzu gösterir
[iPhone Kamera]  → Otomatik çekimler yapar (LiDAR desteğiyle)
[PhotogrammetrySession] → Cihaz üzerinde 3D mesh üretir
[Çıktı]         → USDZ (Apple AR formatı) / web için GLB
```

---

## Gereksinimler

| Gereksinim | Detay |
|-----------|-------|
| Cihaz | iPhone 12 Pro+ (LiDAR önerilir), iPhone 15+ (LiDAR'sız da çalışır) |
| iOS | 17.0+ |
| Xcode | 15.0+ |
| macOS | Sonoma 14.0+ (geliştirme için) |
| Framework | RealityKit 4.0, ARKit |

> **Not:** LiDAR olmayan cihazlarda `ObjectCaptureSession.isSupported` `false` dönebilir. iPhone 15 Pro ile en iyi sonuç alınır.

---

## Proje Yapısı

```
ModuleA_iOS/Snap3DCapture/Snap3DCapture/
├── Snap3DCaptureApp.swift    ← @main giriş noktası
├── ContentView.swift         ← State machine (ready→capture→reconstruct→done)
├── AppDataModel.swift        ← ObjectCaptureSession + PhotogrammetrySession yönetimi
├── HomeView.swift            ← Ana ekran, cihaz uyumluluk kontrolü
├── CaptureView.swift         ← ObjectCaptureView (Apple native AR tarama UI)
├── ReconstructionView.swift  ← 3D model oluşturma progress ekranı
├── CompletedView.swift       ← USDZ paylaşım + AR önizleme + embed kodu
├── ErrorView.swift           ← Hata ekranı
└── Info.plist                ← Kamera izinleri, ARKit, LiDAR gereksinimleri
```

---

## Xcode'da Proje Kurulumu

### 1. Yeni Xcode Projesi Oluştur (Mac'te)
```
Xcode → File → New → Project
→ iOS → App
→ Product Name: Snap3DCapture
→ Team: (Apple Developer hesabınız)
→ Bundle Identifier: com.snap3d.capture
→ Interface: SwiftUI
→ Language: Swift
```

### 2. Dosyaları Kopyala
`ModuleA_iOS/Snap3DCapture/Snap3DCapture/` içindeki tüm `.swift` ve `Info.plist` dosyalarını Xcode projesine sürükle-bırak yap.

### 3. Framework Ekle
```
Project Settings → General → Frameworks, Libraries
→ + → RealityKit.framework → Add
```

### 4. Build Settings
```
Minimum Deployments → iOS 17.0
Signing & Capabilities → + Capability → Camera, Photo Library
```

### 5. iPhone'a Deploy
```
Xcode → Product → Run (⌘R)
Device selector → Fiziksel iPhone seç (simülatörde çalışmaz)
```

---

## Uygulama Akışı

```
HomeView → "Taramayı Başlat" butonuna bas
CaptureView → ObjectCaptureView açılır
              → Nesnenin etrafında turuncu bounding box görünür
              → Kullanıcı telefonu nesne etrafında döndürür
              → Apple otomatik yön kılavuzu verir ("Sola git", "Yukarı eğ" vb.)
              → "Taramayı Tamamla" butonuna bas
ReconstructionView → PhotogrammetrySession cihazda çalışır (~2-8 dk)
CompletedView → USDZ hazır
              → AR'da Önizle: QuickLook ile gerçek ortamda görüntüle
              → USDZ Paylaş: AirDrop / Mail / Dosyalar
              → Web Embed Kodu Al: Panoya kopyalanır
```

---

## Çıktı Türleri

| Format | Kullanım |
|--------|---------|
| `.usdz` | iPhone/iPad AR Quick Look, Reality Composer Pro |
| `.glb` | Web (`<model-viewer>`), Snap3D viewer (Blender ile dönüştür) |

### USDZ → GLB Dönüşümü (İsteğe Bağlı)
```powershell
# Blender ile
blender --background --python ModuleC_Blender/blender_optimizer.py -- \
    --input model.usdz --output model.glb
```

---

## Android için

Android cihazlarda mevcut Unity AR yolu (`DomeCaptureManager.cs`) kullanılır:
- ARCore destekli cihazlarda 30 fotoğraf çekilir
- `FileUploadManager.cs` → `http://<IP>:8765/upload` → Meshroom → Blender → GLB

---

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| `ObjectCaptureSession.isSupported = false` | iPhone 12 Pro+ veya iPhone 15+ kullanın |
| Kamera izni reddedildi | Ayarlar → Snap3D → Kamera → Açık |
| Simülatörde çalışmaz | Fiziksel cihaz gereklidir |
| Fotogrametri çok yavaş | Yüksek ışıklı ortamda, nesneyi açık zemine koy |
| `lidar` capability eksik | `UIRequiredDeviceCapabilities` → `lidar` satırını kaldır |
