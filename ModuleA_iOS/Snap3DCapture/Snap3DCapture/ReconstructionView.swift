// ReconstructionView.swift
// Snap3D — 3D Model Oluşturma Ekranı
// PhotogrammetrySession cihaz üzerinde çalışırken ilerlemeyi gösterir.

import SwiftUI

struct ReconstructionView: View {
    @ObservedObject var appModel: AppDataModel

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Animasyonlu küre ikonu
                SpinningCubeView()

                VStack(spacing: 12) {
                    Text("Model Oluşturuluyor")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(phaseLabel)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .animation(.easeInOut, value: appModel.reconstructionProgress)
                }

                // İlerleme çubuğu
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.1))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.48, green: 0.36, blue: 1.0),
                                                 Color(red: 0.0, green: 0.83, blue: 1.0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(appModel.reconstructionProgress))
                                .animation(.spring(response: 0.5), value: appModel.reconstructionProgress)
                        }
                    }
                    .frame(height: 10)
                    .padding(.horizontal, 32)

                    Text("\(Int(appModel.reconstructionProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text("Bu işlem cihazınızın işlemci hızına göre\nbilrkaç dakika sürebilir.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)

                Spacer()

                // İptal butonu
                Button(action: { appModel.reset() }) {
                    Text("İptal Et")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var phaseLabel: String {
        let p = appModel.reconstructionProgress
        if p < 0.15 { return "Görüntüler analiz ediliyor…" }
        if p < 0.4  { return "Özellik noktaları eşleştiriliyor…" }
        if p < 0.65 { return "3D mesh oluşturuluyor…" }
        if p < 0.85 { return "Dokular uygulanıyor…" }
        return "Son rötuşlar yapılıyor…"
    }
}

// MARK: - Dönen Küp Animasyonu
struct SpinningCubeView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "cube.transparent.fill")
            .font(.system(size: 80))
            .foregroundStyle(
                LinearGradient(
                    colors: [.purple, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            .shadow(color: .purple.opacity(0.4), radius: 20)
    }
}
