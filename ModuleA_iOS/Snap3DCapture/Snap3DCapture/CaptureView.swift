// CaptureView.swift
// Snap3D — AR Tarama Ekranı
//
// Apple'ın ObjectCaptureView'ını kullanarak nesneyi tarar.
// ObjectCaptureView simülatörde mevcut değildir.

import SwiftUI

#if !targetEnvironment(simulator)
import RealityKit
#endif

struct CaptureView: View {
    @ObservedObject var appModel: AppDataModel

    var body: some View {
        #if targetEnvironment(simulator)
        // Simulator: Stub görünüm
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.15).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.gray)
                Text("ObjectCaptureView")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Simulator'da AR tarama desteklenmiyor.\nFiziksel iPhone gereklidir.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                Button("Geri Dön") { appModel.reset() }
                    .foregroundStyle(.blue)
            }
        }
        #else
        ZStack {
            if let session = appModel.captureSession {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()

                VStack {
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
                        Image(systemName: "camera.circle.fill")
                            .font(.title2)
                            .foregroundStyle(feedbackIconColor)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

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
        #endif
    }

    #if !targetEnvironment(simulator)
    private var feedbackIconColor: Color {
        appModel.feedbackMessages.isEmpty ? .green : .yellow
    }
    #endif
}
