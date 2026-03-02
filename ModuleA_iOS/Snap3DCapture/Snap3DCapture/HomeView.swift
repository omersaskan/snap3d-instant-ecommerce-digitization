// HomeView.swift
// Snap3D — Ana Ekran
// Kullanıcıyı taramaya yönlendirir ve cihaz uyumluluğunu kontrol eder.

import SwiftUI

struct HomeView: View {
    @ObservedObject var appModel: AppDataModel
    @State private var showCompatibilityAlert = false

    var body: some View {
        ZStack {
            // Arka plan gradyanı
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.08, green: 0.04, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.48, green: 0.36, blue: 1.0),
                                         Color(red: 0.0, green: 0.83, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .purple.opacity(0.5), radius: 24)

                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 24)

                // Başlık
                Text("Snap3D")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.7, green: 0.55, blue: 1.0),
                                     Color(red: 0.0, green: 0.83, blue: 1.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Instant 3B Model Tarayıcı")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 6)

                Spacer().frame(height: 48)

                // Özellik kartları
                VStack(spacing: 12) {
                    FeatureRow(icon: "arkit", title: "Cihaz Üzerinde AR Tarama",
                               subtitle: "Apple Object Capture ile sunucu gerektirmez")
                    FeatureRow(icon: "cube.fill", title: "USDZ & GLB Çıktısı",
                               subtitle: "Doğrudan web'e veya AR'a ekleyin")
                    FeatureRow(icon: "cpu", title: "On-Device İşleme",
                               subtitle: "PhotogrammetrySession ile yüksek kalite")
                }
                .padding(.horizontal, 24)

                Spacer()

                // Cihaz uyumluluk badge'i
                HStack {
                    Image(systemName: AppDataModel.isSupported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(AppDataModel.isSupported ? .green : .orange)
                    Text(AppDataModel.isSupported
                         ? "Bu cihaz Object Capture'ı destekliyor"
                         : "iPhone 12 Pro veya üzeri gereklidir")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 16)

                // Başla butonu
                Button(action: {
                    if AppDataModel.isSupported {
                        appModel.startCapture()
                    } else {
                        showCompatibilityAlert = true
                    }
                }) {
                    Label("Taramayı Başlat", systemImage: "viewfinder.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.48, green: 0.36, blue: 1.0),
                                         Color(red: 0.35, green: 0.24, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .shadow(color: .purple.opacity(0.45), radius: 16, y: 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .alert("Cihaz Uyumlu Değil", isPresented: $showCompatibilityAlert) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Object Capture, iPhone 12 Pro veya üzeri modeller ve iOS 17.0+ gerektirir.")
        }
    }
}

// MARK: - Yardımcı Bileşenler

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .cyan],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
