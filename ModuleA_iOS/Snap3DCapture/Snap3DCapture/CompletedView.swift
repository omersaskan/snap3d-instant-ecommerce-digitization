// CompletedView.swift
// Snap3D — Model Hazır Ekranı
// USDZ dosyasını paylaşma, AR'da önizleme ve web embed seçenekleri sunar.

import SwiftUI
import QuickLook

struct CompletedView: View {
    @ObservedObject var appModel: AppDataModel
    @State private var showShareSheet  = false
    @State private var showQuickLook   = false
    @State private var showEmbedSheet  = false
    @State private var embedCopied     = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Başlık
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.green, .cyan],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .green.opacity(0.35), radius: 16)
                        .padding(.top, 48)

                    Text("Model Hazır!")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    if let url = appModel.outputModelURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.bottom, 32)

                // ── 3B Önizleme Alanı ──────────────────────────────────────
                if let modelURL = appModel.outputModelURL {
                    Button(action: { showQuickLook = true }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.purple.opacity(0.5), .cyan.opacity(0.3)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )

                            VStack(spacing: 10) {
                                Image(systemName: "arkit")
                                    .font(.system(size: 40))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.purple, .cyan],
                                                       startPoint: .top, endPoint: .bottom)
                                    )
                                Text("AR'da Önizle")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Gerçek ortamınıza yerleştirin")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(24)
                        }
                    }
                    .frame(height: 140)
                    .padding(.horizontal, 24)

                    // ── Eylem Butonları ──────────────────────────────────––
                    VStack(spacing: 12) {
                        ActionButton(
                            title: "USDZ Olarak Paylaş",
                            subtitle: "AirDrop, Mail, Dosyalar…",
                            icon: "square.and.arrow.up.fill",
                            gradient: [Color(red: 0.48, green: 0.36, blue: 1.0), Color(red: 0.3, green: 0.2, blue: 0.9)]
                        ) {
                            showShareSheet = true
                        }

                        ActionButton(
                            title: embedCopied ? "✓ Embed Kodu Kopyalandı!" : "Web Embed Kodu Al",
                            subtitle: "model-viewer iframe kodu",
                            icon: "chevron.left.forwardslash.chevron.right",
                            gradient: [Color(red: 0.0, green: 0.6, blue: 0.8), Color(red: 0.0, green: 0.4, blue: 0.7)]
                        ) {
                            copyEmbedCode(for: modelURL)
                        }

                        ActionButton(
                            title: "Yeni Tarama Başlat",
                            subtitle: "Başa dön",
                            icon: "arrow.counterclockwise.circle.fill",
                            gradient: [Color(red: 0.3, green: 0.3, blue: 0.3), Color(red: 0.2, green: 0.2, blue: 0.2)]
                        ) {
                            appModel.reset()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    if let size = fileSize(for: modelURL) {
                        Text("Dosya boyutu: \(size)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 12)
                    }
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareSheet) {
            if let url = appModel.outputModelURL {
                ShareSheet(url: url)
            }
        }
        .sheet(isPresented: $showQuickLook) {
            if let url = appModel.outputModelURL {
                QuickLookPreviewWrapper(url: url)
            }
        }
    }

    private func copyEmbedCode(for url: URL) {
        let code = """
<script type="module" src="https://ajax.googleapis.com/ajax/libs/model-viewer/3.4.0/model-viewer.min.js"></script>
<model-viewer
  src="YOUR_MODEL_URL/\(url.lastPathComponent)"
  alt="3B Ürün"
  ar
  ar-modes="webxr scene-viewer quick-look"
  camera-controls
  auto-rotate
  shadow-intensity="1"
  style="width:100%;height:480px;">
</model-viewer>
"""
        UIPasteboard.general.string = code
        withAnimation { embedCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { embedCopied = false }
        }
    }

    private func fileSize(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return nil }
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Yardımcı Bileşenler

struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QuickLook Preview Wrapper (sheet-based, no Binding<URL?> extension needed)
struct QuickLookPreviewWrapper: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
