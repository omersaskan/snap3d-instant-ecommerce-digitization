using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using TMPro;

namespace Snap3D
{
    /// <summary>
    /// Snap3D — Çekim İlerleme Arayüzü (Modül A)
    /// 
    /// Dome yüzeyindeki her çekilen açıyı yeşil noktayla işaretler.
    /// İlerleme yüzdesini ve tamamlanma mesajını UI'da gösterir.
    /// </summary>
    public class CaptureProgressUI : MonoBehaviour
    {
        // ─── Inspector Parametreleri ───────────────────────────────────────────
        [Header("UI Referansları")]
        [SerializeField] private TextMeshProUGUI progressLabel;
        [SerializeField] private Slider progressSlider;
        [SerializeField] private GameObject completionPanel;
        [SerializeField] private TextMeshProUGUI completionMessage;
        [SerializeField] private TextMeshProUGUI instructionLabel;

        [Header("Nokta İşaretleri")]
        [Tooltip("Dome yüzeyinde çekilen açıyı temsil eden 3D sprite/dot prefab")]
        [SerializeField] private GameObject capturedDotPrefab;
        [Tooltip("Dot rengi — çekilmemiş açı")]
        [SerializeField] private Color pendingColor = new Color(1f, 1f, 1f, 0.3f);
        [Tooltip("Dot rengi — çekilmiş açı")]
        [SerializeField] private Color capturedColor = new Color(0.2f, 1f, 0.4f, 0.9f);
        [Tooltip("Dot boyutu (dünya birimleri)")]
        [SerializeField] private float dotSize = 0.04f;

        [Header("Renk Aşamaları")]
        [SerializeField] private Color phase1Color = new Color(1f, 0.4f, 0.1f, 1f); // 0–33%
        [SerializeField] private Color phase2Color = new Color(1f, 0.9f, 0.1f, 1f); // 34–66%
        [SerializeField] private Color phase3Color = new Color(0.1f, 1f, 0.4f, 1f); // 67–100%

        // ─── Dahili Durum ──────────────────────────────────────────────────────
        private readonly List<GameObject> _dots = new();
        private int _lastCaptured = 0;
        private int _target = 30;

        // ─── Mesaj Dizileri ───────────────────────────────────────────────────
        private static readonly string[] InstructionMessages = {
            "Telefonu kubbenin etrafında yavaşça gezdirin.",
            "Harika! Biraz daha devam edin.",
            "Çok iyi, sona yaklaşıyorsunuz!",
            "Son birkaç açı kaldı — neredeyse bitti!"
        };

        // ─── Public API ───────────────────────────────────────────────────────

        /// <summary>
        /// İlerleme çubuğunu ve etiketini güncelle.
        /// </summary>
        public void UpdateProgress(int captured, int total)
        {
            _target = total;
            _lastCaptured = captured;

            float ratio = total > 0 ? (float)captured / total : 0f;

            if (progressLabel != null)
                progressLabel.text = $"{captured} / {total}  ({ratio * 100f:F0}%)";

            if (progressSlider != null)
            {
                progressSlider.value = ratio;
                // Slider dolgu rengini aşamaya göre değiştir
                var fill = progressSlider.fillRect?.GetComponent<Image>();
                if (fill != null)
                    fill.color = GetPhaseColor(ratio);
            }

            UpdateInstructionLabel(ratio);
        }

        /// <summary>
        /// Dome üzerinde verilen 3D pozisyona yeşil nokta koy ve ilerlemeyi güncelle.
        /// </summary>
        public void MarkAngleCaptured(Vector3 worldPosition, int captured, int total)
        {
            // Dot oluştur veya yeniden kullan
            GameObject dot;
            if (capturedDotPrefab != null)
            {
                dot = Instantiate(capturedDotPrefab, worldPosition, Quaternion.identity);
            }
            else
            {
                dot = CreateBuiltinDot(worldPosition);
            }

            dot.name = $"CapturedDot_{captured}";
            _dots.Add(dot);

            // Kamera'ya yönelik: Billboard efekti için Update'te de yapılabilir
            // Ama basitlik için sadece normal yönde bırakıyoruz

            // Renk animasyonu: önce beyaz flash, sonra capture rengine geç
            StartCoroutine(AnimateDot(dot));

            // İlerleme UI'ını güncelle
            UpdateProgress(captured, total);
        }

        /// <summary>
        /// Tüm çekimler tamamlandığında completion panel'i göster.
        /// </summary>
        public void ShowCompletionMessage(string sessionDirectory)
        {
            if (completionPanel != null)
                completionPanel.SetActive(true);

            if (completionMessage != null)
                completionMessage.text =
                    $"✓ {_target} fotoğraf çekildi!\n" +
                    $"İşleme başlıyor...\n\n" +
                    $"Kayıt: {sessionDirectory}";

            if (instructionLabel != null)
                instructionLabel.text = "Harika! Model oluşturuluyor...";
        }

        /// <summary>
        /// Tüm noktaları temizle (yeni oturum için).
        /// </summary>
        public void Reset()
        {
            foreach (var dot in _dots)
                if (dot != null) Destroy(dot);
            _dots.Clear();

            UpdateProgress(0, _target);

            if (completionPanel != null)
                completionPanel.SetActive(false);
        }

        // ─── Dahili Yardımcılar ───────────────────────────────────────────────

        private System.Collections.IEnumerator AnimateDot(GameObject dot)
        {
            var renderer = dot.GetComponent<Renderer>();
            if (renderer == null) yield break;

            // Flash: beyaz
            renderer.material.color = Color.white;
            yield return new WaitForSeconds(0.1f);

            // Hedef renge geç
            renderer.material.color = capturedColor;

            // Küçük büyüyüp küçülme animasyonu
            float elapsed = 0f;
            float duration = 0.3f;
            Vector3 originalScale = dot.transform.localScale;
            Vector3 peakScale = originalScale * 1.6f;

            while (elapsed < duration)
            {
                elapsed += Time.deltaTime;
                float t = elapsed / duration;
                // Ease-out: büyü ve geri dön
                float scale = t < 0.5f
                    ? Mathf.Lerp(1f, 1.6f, t * 2f)
                    : Mathf.Lerp(1.6f, 1f, (t - 0.5f) * 2f);
                dot.transform.localScale = originalScale * scale;
                yield return null;
            }

            dot.transform.localScale = originalScale;
        }

        private GameObject CreateBuiltinDot(Vector3 position)
        {
            var dot = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            dot.transform.position = position;
            dot.transform.localScale = Vector3.one * dotSize;

            // Collider kaldır
            Destroy(dot.GetComponent<Collider>());

            var mat = new Material(Shader.Find("Sprites/Default"));
            mat.color = pendingColor;
            dot.GetComponent<Renderer>().material = mat;

            return dot;
        }

        private Color GetPhaseColor(float ratio)
        {
            if (ratio < 0.33f)   return Color.Lerp(phase1Color, phase2Color, ratio / 0.33f);
            if (ratio < 0.67f)   return Color.Lerp(phase2Color, phase3Color, (ratio - 0.33f) / 0.34f);
            return phase3Color;
        }

        private void UpdateInstructionLabel(float ratio)
        {
            if (instructionLabel == null) return;

            int idx = ratio < 0.25f ? 0
                    : ratio < 0.5f  ? 1
                    : ratio < 0.85f ? 2
                    : 3;

            instructionLabel.text = InstructionMessages[idx];
        }

        // ─── Unity Lifecycle ──────────────────────────────────────────────────
        private void Start()
        {
            if (completionPanel != null)
                completionPanel.SetActive(false);

            UpdateProgress(0, _target);
        }
    }
}
