// ContentView.swift
// Snap3D — Ana Ekran
// Tarama → İşleme → Dışa Aktarma akışını yönetir

import SwiftUI

struct ContentView: View {

    @StateObject private var appModel = AppDataModel()

    var body: some View {
        Group {
            switch appModel.state {
            case .ready:
                HomeView(appModel: appModel)

            case .capturing:
                CaptureView(appModel: appModel)

            case .reconstructing:
                ReconstructionView(appModel: appModel)

            case .completed:
                CompletedView(appModel: appModel)

            case .failed(let error):
                ErrorView(error: error, appModel: appModel)
            }
        }
        .animation(.easeInOut, value: appModel.state)
    }
}

// MARK: - Durum Enum

enum AppState: Equatable {
    case ready
    case capturing
    case reconstructing
    case completed
    case failed(String)

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready), (.capturing, .capturing),
             (.reconstructing, .reconstructing), (.completed, .completed):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
