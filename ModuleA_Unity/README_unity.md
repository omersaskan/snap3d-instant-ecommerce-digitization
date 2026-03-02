# Modül A: Unity AR Foundation Yakalama Arayüzü

AR Foundation kullanarak nesnenin etrafında 1 metre yarıçaplı wireframe dome oluşturur. Kamera 15 derece hareket ettikçe otomatik fotoğraf çeker ve `Application.persistentDataPath` altına kaydeder.

---

## Gereksinimler

| Araç | Sürüm |
|------|-------|
| Unity | 2022.3 LTS veya 2023.1+ |
| AR Foundation | 5.1+ |
| ARCore (Android) | 1.40+ |
| ARKit (iOS) | 5.0+ |
| TextMeshPro | Herhangi |

---

## Unity Paket Kurulumu

**Window → Package Manager** üzerinden:

```
AR Foundation          → 5.x
Google ARCore XR Plugin → 5.x (Android için)
Apple ARKit XR Plugin  → 5.x (iOS için)
```

---

## Sahne Kurulumu

### 1. AR Session Nesnesi

```
Hierarchy:
└── AR Session Origin
    └── AR Camera
        └── (kameranın üstüne eklenen bileşenler)
```

**AR Session** ve **AR Session Origin** objelerini Unity menüsünden ekle:
`GameObject → XR → AR Session` ve `GameObject → XR → AR Session Origin`

### 2. DomeCaptureManager Bileşeni

Ana sahne objesine `DomeCaptureManager.cs` scriptini ekle ve Inspector'da şunları ata:

| Alan | Değer |
|------|-------|
| AR Session | Sahnedeki `AR Session` objesi |
| AR Plane Manager | `AR Session Origin` üzerindeki bileşen |
| AR Camera | `AR Camera` objesi |
| Progress UI | CaptureProgressUI bileşeni |
| Dome Radius | `1.0` (metre) |
| Capture Angle Step | `15` (derece) |
| Target Photo Count | `30` |

### 3. CaptureProgressUI Bileşeni

Bir UI Canvas altında boş bir GameObject oluştur, `CaptureProgressUI.cs` ekle:

| Alan | Değer |
|------|-------|
| Progress Label | Text (TMP) objesi |
| Progress Slider | Slider objesi |
| Completion Panel | Tamamlanma paneli (başlangıçta inactive) |
| Captured Dot Prefab | Küçük yeşil sphere (opsiyonel, yoksa yerleşik oluşturulur) |

### 4. FileUploadManager Bileşeni (Opsiyonel)

Aynı objeye `FileUploadManager.cs` ekle:

| Alan | Değer |
|------|-------|
| Upload Mode | `LocalNetwork` veya `S3PresignedUrl` |
| Local Endpoint | `http://192.168.1.100:8765/upload` |

---

## Build Ayarları

### Android
1. `File → Build Settings → Android`
2. `Player Settings → Other Settings`:
   - **Minimum API Level:** Android 7.0 (API 24)
   - **Target API Level:** Android 13+
   - **Graphics API:** OpenGLES3 veya Vulkan

3. `Player Settings → XR Plug-in Management → Android → ARCore` ✓

### iOS
1. `File → Build Settings → iOS`
2. `Player Settings → Other Settings`:
   - **Camera Usage Description:** "Ürünü 3B taramak için kamera gereklidir."
   - **Minimum iOS Version:** 14.0
3. `Player Settings → XR Plug-in Management → iOS → ARKit` ✓

---

## Çalışma Zamanı Akışı

```
[BAŞLAT]  → AR düzlem tespiti başlar
[DÜZLEM]  → İlk yatay yüzey bulunur
[DOME]    → Wireframe yarım küre nesnenin üzerine yerleşir
[HAZIR]   → Kullanıcı dome çevresinde yürümeye başlar
[ÇEKIM]   → Her 15°'de otomatik screenshot çekilir, nokta yeşile döner
[TAMAMDI] → 30 fotoğraf birikir, FileUploadManager tetiklenir
[YÜKLEME] → Fotoğraflar Python watchdog'a gönderilir
```

---

## Fotoğrafların Konumu

```
Android: /storage/emulated/0/Android/data/com.yourcompany.snap3d/files/Snap3DCaptures/YYYYMMDD_HHmmss/
iOS:     /var/mobile/Containers/Data/Application/<UUID>/Documents/Snap3DCaptures/YYYYMMDD_HHmmss/
```

---

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| Dome görünmüyor | Yatay düzlem tespit edilmesini bekle (masa/zemin) |
| Fotoğraf çekilmiyor | AR Camera referansının Inspector'da atandığını kontrol et |
| Build hatası: namespace | TextMeshPro paketini kur ya da `TMPro` yerine `UnityEngine.UI.Text` kullan |
| Yükleme başarısız | Python watchdog'un aynı WiFi ağında çalıştığını doğrula |
