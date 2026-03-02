// CaptureView.swift
// Snap3D — AR Tarama Ekranı
//
// Apple'ın ObjectCaptureView'ını kullanarak nesneyi tarar.
// Rules.txt'deki "AR Rehber + Akıllı Çekim" modülüne karşılık gelir.
// ObjectCaptureView otomatik olarak kılavuz gösterir, döndürme yönlendirmesi
// yapar ve kullanıcıyı "Tamamla" aşamasına götürür.

import SwiftUI
import RealityKit

struct CaptureView: View {
    @ObservedObject var appModel: AppDataModel

    var body: some View {
        ZStack {

            // ── Apple'ın Native AR Tarama Görünümü ──────────────────────────
            // ObjectCaptureView:
            //  • Kamera görüntüsü + nesne etrafında AR bounding box
            //  • Kullanıcıya "sola git", "yukarı git" yönlendirmesi
            //  • Çekilen açıları yeşil olarak işaretler (tam rules.txt gibi)
            //  • Otomatik döndürme tamamlama önerisi
            if let session = appModel.captureSession {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()

                // Overlay UI
                VStack {
                    // ── Başlık ─────────────────────────────────────────────
                    HStack {
                        Button(action: { appModel.reset() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                        Text("Snap3D Tarama")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        // ARCore Geri bildirim göstergesi
                        Image(systemName: "camera.circle.fill")
                            .font(.title2)
                            .foregroundStyle(feedbackIconColor)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    // ── Feedback Mesajları ─────────────────────────────────
                    if !appModel.feedbackMessages.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(appModel.feedbackMessages, id: \.self) { msg in
                                Text(msg)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.85), in: Capsule())
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: appModel.feedbackMessages)
                    }

                    // ── Tamamla Butonu ─────────────────────────────────────
                    // ObjectCaptureSession'ın userCompletedScanPass değeri
                    // true olduğunda bu butonu göster
                    Button(action: { appModel.finishCapture() }) {
                        Label("Taramayı Tamamla", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.3, green: 0.6, blue: 1.0),
                                             Color(red: 0.1, green: 0.4, blue: 0.9)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // Geri bildirim varsa sarı, yoksa yeşil ikon
    private var feedbackIconColor: Color {
        appModel.feedbackMessages.isEmpty ? .green : .yellow
    }
}
