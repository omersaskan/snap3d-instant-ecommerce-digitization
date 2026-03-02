// ErrorView.swift
// Snap3D — Hata Ekranı

import SwiftUI

struct ErrorView: View {
    let error: String
    @ObservedObject var appModel: AppDataModel

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.15).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.4), radius: 16)

                Text("Bir Sorun Oluştu")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: { appModel.reset() }) {
                    Label("Yeniden Dene", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
            }
        }
        .preferredColorScheme(.dark)
    }
}
