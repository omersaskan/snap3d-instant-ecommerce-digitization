using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;

namespace Snap3D
{
    /// <summary>
    /// Snap3D — AR Dome Yakalama Yöneticisi (Modül A)
    /// 
    /// AR Foundation kullanarak nesnenin etrafında 1 metre yarıçaplı
    /// wireframe yarım küre oluşturur. Kamera her 15 derecede bir hareket
    /// ettiğinde otomatik fotoğraf çeker ve Application.persistentDataPath
    /// altına kaydeder. Jiroskop yerine AR kamera rotasyon verisi kullanılır.
    /// </summary>
    public class DomeCaptureManager : MonoBehaviour
    {
        // ─── Inspector Parametreleri ───────────────────────────────────────────
        [Header("AR Bileşenleri")]
        [SerializeField] private ARSession arSession;
        [SerializeField] private ARPlaneManager arPlaneManager;
        [SerializeField] private Camera arCamera;

        [Header("Dome Ayarları")]
        [SerializeField] private float domeRadius = 1.0f;
        [SerializeField] private GameObject domeWireframePrefab;
        [Tooltip("Fotoğraf çekilecek minimum açı değişimi (derece)")]
        [SerializeField] private float captureAngleStep = 15f;
        [Tooltip("Yatay düzleme göre maksimum çekim eğimi (derece)")]
        [SerializeField] private float maxPitchAngle = 80f;

        [Header("Çekim Ayarları")]
        [SerializeField] private int targetPhotoCount = 30;
        [SerializeField] private float captureDelaySeconds = 0.5f;
        [Tooltip("Çekimler arası minimum süre (saniye) — titreme önleme")]
        [SerializeField] private float minCaptureInterval = 0.8f;

        [Header("Geri Bildirim")]
        [SerializeField] private CaptureProgressUI progressUI;

        // ─── Dahili Durum ──────────────────────────────────────────────────────
        private GameObject _domeInstance;
        private Vector3 _domeCenter;
        private bool _isDomePlaced = false;
        private bool _isCapturing = false;

        // Her kamera pozisyonu için açı takibi
        // Key: (azimuthBucket, elevationBucket) → çekilen fotoğraf sayısı
        private readonly Dictionary<(int az, int el), int> _capturedAngles
            = new Dictionary<(int, int), int>();

        private float _lastCaptureTime = -999f;
        private int _totalCaptured = 0;
        private string _sessionDir;

        // ─── Sabitler ─────────────────────────────────────────────────────────
        private const string SESSION_ROOT = "Snap3DCaptures";

        // ─── Unity Lifecycle ──────────────────────────────────────────────────
        private void Awake()
        {
            ValidateComponents();
            CreateSessionDirectory();
        }

        private void Start()
        {
            // AR Plane tespiti: ilk düzlem bulunduğunda dome yerleştir
            if (arPlaneManager != null)
                arPlaneManager.planesChanged += OnPlanesChanged;

            if (progressUI != null)
                progressUI.UpdateProgress(0, targetPhotoCount);
        }

        private void Update()
        {
            if (!_isDomePlaced || _isCapturing || _totalCaptured >= targetPhotoCount)
                return;

            CheckAndCapture();
        }

        private void OnDestroy()
        {
            if (arPlaneManager != null)
                arPlaneManager.planesChanged -= OnPlanesChanged;
        }

        // ─── AR Plane Tespiti ──────────────────────────────────────────────────
        private void OnPlanesChanged(ARPlanesChangedEventArgs args)
        {
            if (_isDomePlaced) return;

            // İlk düzlem tespit edildiğinde dome'u yerleştir
            foreach (var plane in args.added)
            {
                if (plane.classification == PlaneClassification.Floor ||
                    plane.classification == PlaneClassification.Table ||
                    plane.alignment == PlaneAlignment.HorizontalUp)
                {
                    PlaceDome(plane.center);
                    // Artık plane tespitine gerek yok
                    arPlaneManager.enabled = false;
                    break;
                }
            }
        }

        /// <summary>
        /// Dome'u verilen dünye pozisyonuna yerleştir.
        /// Dışarıdan (UI buton vb.) da çağrılabilir.
        /// </summary>
        public void PlaceDome(Vector3 worldPosition)
        {
            if (_isDomePlaced) return;

            _domeCenter = worldPosition;

            if (domeWireframePrefab != null)
            {
                _domeInstance = Instantiate(domeWireframePrefab, worldPosition, Quaternion.identity);
                _domeInstance.transform.localScale = Vector3.one * domeRadius;
            }
            else
            {
                // Prefab yoksa yerleşik basit wireframe oluştur
                _domeInstance = CreateBuiltinWireframeDome(worldPosition);
            }

            _isDomePlaced = true;
            Debug.Log($"[Snap3D] Dome yerleştirildi: {worldPosition} (r={domeRadius}m)");
        }

        // ─── Yakalama Mantığı ─────────────────────────────────────────────────

        /// <summary>
        /// Kameranın mevcut dome-merkezine göre açısını hesapla,
        /// bu açı daha önce çekilmediyse ve yeterli süre geçtiyse fotoğraf çek.
        /// </summary>
        private void CheckAndCapture()
        {
            if (Time.time - _lastCaptureTime < minCaptureInterval)
                return;

            Vector3 camPos = arCamera.transform.position;
            (int az, int el) angleBucket = ComputeAngleBucket(camPos);

            // Bu açı henüz çekilmediyse
            if (!_capturedAngles.ContainsKey(angleBucket))
            {
                // Kameranın dome merkezine bakıp bakmadığını kontrol et (isteğe bağlı)
                // Şimdilik her açıda çekiyoruz
                StartCoroutine(CaptureRoutine(angleBucket, camPos));
            }
        }

        private IEnumerator CaptureRoutine((int az, int el) angleBucket, Vector3 capturePos)
        {
            _isCapturing = true;
            _lastCaptureTime = Time.time;

            // Kısa gecikme: render'ın tamamlanmasını bekle
            yield return new WaitForEndOfFrame();
            yield return new WaitForSeconds(captureDelaySeconds);

            string fileName = $"snap3d_{_totalCaptured + 1:D3}_az{angleBucket.az}_el{angleBucket.el}.png";
            string fullPath = Path.Combine(_sessionDir, fileName);

            ScreenCapture.CaptureScreenshot(fullPath);

            _capturedAngles[angleBucket] = 1;
            _totalCaptured++;
            _lastCaptureTime = Time.time;

            Debug.Log($"[Snap3D] Çekim #{_totalCaptured}: {fileName}");

            // UI güncelle: bu açıyı yeşile boya
            if (progressUI != null)
            {
                Vector3 dirOnDome = (capturePos - _domeCenter).normalized * domeRadius;
                progressUI.MarkAngleCaptured(dirOnDome + _domeCenter, _totalCaptured, targetPhotoCount);
            }

            // Tamamlandı mı?
            if (_totalCaptured >= targetPhotoCount)
            {
                OnCaptureComplete();
            }

            _isCapturing = false;
        }

        private void OnCaptureComplete()
        {
            Debug.Log($"[Snap3D] Çekim tamamlandı! {_totalCaptured} fotoğraf: {_sessionDir}");

            if (progressUI != null)
                progressUI.ShowCompletionMessage(_sessionDir);

            // FileUploadManager varsa tetikle
            var uploader = GetComponent<FileUploadManager>();
            if (uploader != null)
                uploader.UploadSession(_sessionDir);
        }

        // ─── Açı Hesaplama ────────────────────────────────────────────────────

        /// <summary>
        /// Kamera-dome merkezi vektörünü azimuth/elevation bucket'larına dönüştür.
        /// Her bucket = captureAngleStep derece.
        /// </summary>
        private (int az, int el) ComputeAngleBucket(Vector3 camPos)
        {
            Vector3 dir = camPos - _domeCenter;
            if (dir.sqrMagnitude < 0.001f)
                return (0, 0);

            // Azimuth (yatay açı, XZ düzlemi): 0–359 derece
            float azimuth = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
            if (azimuth < 0) azimuth += 360f;

            // Elevation (dikey açı): 0–maxPitchAngle derece
            float elevation = Mathf.Asin(Mathf.Clamp(dir.normalized.y, -1f, 1f)) * Mathf.Rad2Deg;
            elevation = Mathf.Clamp(elevation, 0f, maxPitchAngle);

            int azBucket = Mathf.FloorToInt(azimuth / captureAngleStep);
            int elBucket = Mathf.FloorToInt(elevation / captureAngleStep);

            return (azBucket, elBucket);
        }

        // ─── Oturum Dizini ────────────────────────────────────────────────────
        private void CreateSessionDirectory()
        {
            string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            _sessionDir = Path.Combine(
                Application.persistentDataPath,
                SESSION_ROOT,
                timestamp
            );
            Directory.CreateDirectory(_sessionDir);
            Debug.Log($"[Snap3D] Oturum dizini: {_sessionDir}");
        }

        // ─── Wireframe Dome Oluşturucu (Prefab yoksa) ─────────────────────────
        private GameObject CreateBuiltinWireframeDome(Vector3 center)
        {
            var dome = new GameObject("Snap3D_WireframeDome");
            dome.transform.position = center;

            // Yatay çemberler (latitude rings)
            int latSegments = 6;
            int lonSegments = 24;

            for (int lat = 0; lat <= latSegments; lat++)
            {
                float phi = Mathf.PI * 0.5f * lat / latSegments; // 0 → 90 derece
                float y = Mathf.Sin(phi) * domeRadius;
                float r = Mathf.Cos(phi) * domeRadius;

                var ring = new GameObject($"Ring_{lat}");
                ring.transform.parent = dome.transform;
                ring.transform.localPosition = Vector3.zero;

                var lr = ring.AddComponent<LineRenderer>();
                ConfigureWireframeLineRenderer(lr);

                var points = new Vector3[lonSegments + 1];
                for (int lon = 0; lon <= lonSegments; lon++)
                {
                    float theta = 2 * Mathf.PI * lon / lonSegments;
                    points[lon] = center + new Vector3(
                        r * Mathf.Cos(theta),
                        y,
                        r * Mathf.Sin(theta)
                    );
                }
                lr.positionCount = points.Length;
                lr.SetPositions(points);
            }

            // Dikey çizgiler (meridians)
            for (int lon = 0; lon < lonSegments; lon += 4)
            {
                float theta = 2 * Mathf.PI * lon / lonSegments;
                var meridian = new GameObject($"Meridian_{lon}");
                meridian.transform.parent = dome.transform;
                meridian.transform.localPosition = Vector3.zero;

                var lr = meridian.AddComponent<LineRenderer>();
                ConfigureWireframeLineRenderer(lr);

                var points = new Vector3[latSegments + 1];
                for (int lat = 0; lat <= latSegments; lat++)
                {
                    float phi = Mathf.PI * 0.5f * lat / latSegments;
                    points[lat] = center + new Vector3(
                        Mathf.Cos(phi) * Mathf.Cos(theta) * domeRadius,
                        Mathf.Sin(phi) * domeRadius,
                        Mathf.Cos(phi) * Mathf.Sin(theta) * domeRadius
                    );
                }
                lr.positionCount = points.Length;
                lr.SetPositions(points);
            }

            return dome;
        }

        private static void ConfigureWireframeLineRenderer(LineRenderer lr)
        {
            lr.material = new Material(Shader.Find("Sprites/Default"));
            lr.startColor = new Color(0.2f, 0.8f, 1f, 0.6f);
            lr.endColor   = new Color(0.2f, 0.8f, 1f, 0.6f);
            lr.startWidth = 0.004f;
            lr.endWidth   = 0.004f;
            lr.loop = false;
            lr.useWorldSpace = true;
        }

        // ─── Doğrulama ────────────────────────────────────────────────────────
        private void ValidateComponents()
        {
            if (arCamera == null)
                arCamera = Camera.main;

            if (arCamera == null)
                Debug.LogError("[Snap3D] AR Camera bulunamadı! Inspector'dan atayın.");
        }

        // ─── Public API ───────────────────────────────────────────────────────
        public int TotalCaptured => _totalCaptured;
        public int TargetPhotoCount => targetPhotoCount;
        public string SessionDirectory => _sessionDir;
        public bool IsCaptureComplete => _totalCaptured >= targetPhotoCount;

        /// <summary>
        /// Dome'u manuel olarak belirli bir pozisyona yerleştir (UI butonu için).
        /// </summary>
        public void PlaceDomeAtTapPosition(Vector3 hitPoint) => PlaceDome(hitPoint);

        /// <summary>
        /// Mevcut oturum dizinini döndür (FileUploadManager için).
        /// </summary>
        public string GetSessionDirectory() => _sessionDir;
    }
}
