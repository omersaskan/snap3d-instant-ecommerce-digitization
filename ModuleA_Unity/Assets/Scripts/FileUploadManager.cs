using System;
using System.Collections;
using System.IO;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace Snap3D
{
    /// <summary>
    /// Snap3D — Dosya Yükleme Yöneticisi (Modül A)
    /// 
    /// Çekim tamamlandığında fotoğrafları:
    ///   1. Yerel ağdaki Python watchdog sunucusuna (HTTP multipart)
    ///   2. Veya AWS S3 presigned URL aracılığıyla
    /// yükler. Yapılandırma Inspector'da yapılır.
    /// </summary>
    public class FileUploadManager : MonoBehaviour
    {
        // ─── Inspector Parametreleri ───────────────────────────────────────────
        [Header("Yükleme Modu")]
        [SerializeField] private UploadMode uploadMode = UploadMode.LocalNetwork;

        [Header("Yerel Ağ (HTTP)")]
        [Tooltip("Python watchdog sunucusunun HTTP endpoint'i")]
        [SerializeField] private string localEndpoint = "http://192.168.1.100:8765/upload";
        [Tooltip("Bağlantı zaman aşımı (saniye)")]
        [SerializeField] private float timeoutSeconds = 30f;

        [Header("S3 Presigned URL (opsiyonel)")]
        [Tooltip("Her dosya için ayrı presigned URL oluşturan backend endpoint")]
        [SerializeField] private string presignedUrlEndpoint = "https://your-api.example.com/presign";
        [SerializeField] private string apiKey = "";

        [Header("UI Geri Bildirimi")]
        [SerializeField] private CaptureProgressUI progressUI;
        [SerializeField] private TMPro.TextMeshProUGUI uploadStatusLabel;

        // ─── Enum ─────────────────────────────────────────────────────────────
        public enum UploadMode
        {
            LocalNetwork,   // HTTP multipart POST → Python watchdog
            S3PresignedUrl, // AWS S3 presigned URL via backend
            Disabled        // Sadece yerel kayıt
        }

        // ─── Public API ───────────────────────────────────────────────────────

        /// <summary>
        /// Verilen oturum dizinindeki tüm PNG/JPG dosyalarını yükle.
        /// DomeCaptureManager tarafından çekim bitince çağrılır.
        /// </summary>
        public void UploadSession(string sessionDirectory)
        {
            if (uploadMode == UploadMode.Disabled)
            {
                Debug.Log("[Snap3D Upload] Yükleme devre dışı. Dosyalar yerel kayıtta.");
                SetStatus("✓ Yerel kayıt tamamlandı.");
                return;
            }

            StartCoroutine(UploadAllFiles(sessionDirectory));
        }

        // ─── Yükleme Korutinleri ──────────────────────────────────────────────

        private IEnumerator UploadAllFiles(string directory)
        {
            string[] files = Directory.GetFiles(directory, "*.png");
            if (files.Length == 0)
                files = Directory.GetFiles(directory, "*.jpg");

            if (files.Length == 0)
            {
                Debug.LogWarning($"[Snap3D Upload] Yüklenecek dosya bulunamadı: {directory}");
                SetStatus("Yüklenecek dosya yok.");
                yield break;
            }

            Debug.Log($"[Snap3D Upload] {files.Length} dosya yüklenecek. Mod: {uploadMode}");
            SetStatus($"Yükleniyor: 0 / {files.Length}");

            int successCount = 0;
            int failCount = 0;

            for (int i = 0; i < files.Length; i++)
            {
                string filePath = files[i];
                SetStatus($"Yükleniyor: {i + 1} / {files.Length}  ({Path.GetFileName(filePath)})");

                bool success = false;

                switch (uploadMode)
                {
                    case UploadMode.LocalNetwork:
                        yield return StartCoroutine(
                            UploadToLocal(filePath, result => success = result)
                        );
                        break;

                    case UploadMode.S3PresignedUrl:
                        yield return StartCoroutine(
                            UploadToS3(filePath, result => success = result)
                        );
                        break;
                }

                if (success) successCount++;
                else failCount++;

                // Kısa aralık: sunucuyu boğma
                yield return new WaitForSeconds(0.1f);
            }

            string summary = $"✓ {successCount} yüklendi";
            if (failCount > 0) summary += $"  ✗ {failCount} başarısız";
            SetStatus(summary);
            Debug.Log($"[Snap3D Upload] Tamamlandı. {summary}");
        }

        // ─── HTTP Multipart Yükleme (Local) ──────────────────────────────────

        private IEnumerator UploadToLocal(string filePath, Action<bool> callback)
        {
            byte[] fileData;
            try
            {
                fileData = File.ReadAllBytes(filePath);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Snap3D Upload] Dosya okunamadı: {filePath} — {ex.Message}");
                callback(false);
                yield break;
            }

            string fileName = Path.GetFileName(filePath);
            var form = new WWWForm();
            form.AddBinaryData("file", fileData, fileName, "image/png");
            form.AddField("session", Path.GetDirectoryName(filePath) ?? "unknown");

            using var request = UnityWebRequest.Post(localEndpoint, form);
            request.timeout = (int)timeoutSeconds;

            yield return request.SendWebRequest();

            bool ok = request.result == UnityWebRequest.Result.Success;
            if (!ok)
                Debug.LogWarning($"[Snap3D Upload] Hata ({fileName}): {request.error}");

            callback(ok);
        }

        // ─── S3 Presigned URL Yükleme ─────────────────────────────────────────

        private IEnumerator UploadToS3(string filePath, Action<bool> callback)
        {
            // Adım 1: Backend'den presigned URL al
            string fileName = Path.GetFileName(filePath);
            string presignRequestUrl = $"{presignedUrlEndpoint}?filename={UnityWebRequest.EscapeURL(fileName)}";

            using var presignRequest = UnityWebRequest.Get(presignRequestUrl);
            presignRequest.timeout = 15;
            if (!string.IsNullOrEmpty(apiKey))
                presignRequest.SetRequestHeader("x-api-key", apiKey);

            yield return presignRequest.SendWebRequest();

            if (presignRequest.result != UnityWebRequest.Result.Success)
            {
                Debug.LogError($"[Snap3D Upload] Presigned URL alınamadı: {presignRequest.error}");
                callback(false);
                yield break;
            }

            PresignedResponse presignedData;
            try
            {
                presignedData = JsonUtility.FromJson<PresignedResponse>(presignRequest.downloadHandler.text);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Snap3D Upload] Presigned URL ayrıştırma hatası: {ex.Message}");
                callback(false);
                yield break;
            }

            // Adım 2: Dosyayı S3'e PUT
            byte[] fileData;
            try { fileData = File.ReadAllBytes(filePath); }
            catch (Exception ex)
            {
                Debug.LogError($"[Snap3D Upload] Dosya okunamadı: {ex.Message}");
                callback(false);
                yield break;
            }

            using var s3Request = UnityWebRequest.Put(presignedData.url, fileData);
            s3Request.timeout = (int)timeoutSeconds;
            s3Request.SetRequestHeader("Content-Type", "image/png");

            yield return s3Request.SendWebRequest();

            bool ok = s3Request.result == UnityWebRequest.Result.Success;
            if (!ok)
                Debug.LogWarning($"[Snap3D Upload] S3 PUT hatası ({fileName}): {s3Request.error}");

            callback(ok);
        }

        // ─── UI ───────────────────────────────────────────────────────────────
        private void SetStatus(string message)
        {
            if (uploadStatusLabel != null)
                uploadStatusLabel.text = message;
            Debug.Log($"[Snap3D Upload] {message}");
        }

        // ─── Veri Modelleri ───────────────────────────────────────────────────
        [Serializable]
        private class PresignedResponse
        {
            public string url;     // S3 presigned PUT URL
            public string fileKey; // S3 object key (bilgi amaçlı)
        }
    }
}
