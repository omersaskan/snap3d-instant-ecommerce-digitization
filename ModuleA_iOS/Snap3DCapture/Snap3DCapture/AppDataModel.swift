// AppDataModel.swift
// Snap3D — Uygulama Durum Yöneticisi
//
// ObjectCaptureSession + PhotogrammetrySession'ı koordine eder.
// Cihaz üzerinde tüm 3D model üretimini yönetir — sunucu gerektirmez.
//
// NOT: ObjectCaptureSession ve PhotogrammetrySession API'leri
// iOS Simulator'da mevcut DEĞİLDİR. Simulator build'leri için
// stub implementasyon kullanılır.

import Foundation
import SwiftUI
import OSLog

#if !targetEnvironment(simulator)
import RealityKit
import Combine
#endif

private let logger = Logger(subsystem: "com.snap3d.capture", category: "AppDataModel")

@MainActor
final class AppDataModel: ObservableObject {

    // ─── Yayımlanan State ──────────────────────────────────────────────────
    @Published var state: AppState = .ready
    @Published var shotCount: Int = 0
    @Published var feedbackMessages: [String] = []
    @Published var reconstructionProgress: Float = 0.0
    @Published var outputModelURL: URL?
    @Published var outputGLBURL: URL?

    #if !targetEnvironment(simulator)
    @Published var captureSession: ObjectCaptureSession?
    #endif

    // ─── Oturum Dizinleri ─────────────────────────────────────────────────
    private var imagesDirectory: URL?
    private var checkpointDirectory: URL?
    private var outputDirectory: URL?

    // ─── Destekli Cihaz Kontrolü ──────────────────────────────────────────
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ObjectCaptureSession.isSupported
        #endif
    }

    // ─── Yeni Tarama Başlat ───────────────────────────────────────────────
    func startCapture() {
        #if targetEnvironment(simulator)
        state = .failed("Simulator'da Object Capture desteklenmiyor.\nFiziksel iPhone gereklidir.")
        #else
        guard Self.isSupported else {
            state = .failed("Bu cihaz Object Capture'ı desteklemiyor.\niPhone 12 Pro veya üzeri gereklidir.")
            return
        }

        let sessionID = UUID().uuidString
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Snap3D/\(sessionID)")

        imagesDirectory     = tmp.appendingPathComponent("Images")
        checkpointDirectory = tmp.appendingPathComponent("Checkpoints")
        outputDirectory     = tmp.appendingPathComponent("Output")

        do {
            for dir in [imagesDirectory!, checkpointDirectory!, outputDirectory!] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        } catch {
            state = .failed("Dizin oluşturulamadı: \(error.localizedDescription)")
            return
        }

        let session = ObjectCaptureSession()
        captureSession = session
        shotCount = 0
        feedbackMessages = []

        observeSession(session)

        var config = ObjectCaptureSession.Configuration()
        config.checkpointDirectory = checkpointDirectory
        config.isOverCaptureEnabled = true

        session.start(imagesDirectory: imagesDirectory!, configuration: config)
        state = .capturing

        logger.info("ObjectCaptureSession başlatıldı → \(self.imagesDirectory!.path)")
        #endif
    }

    // ─── Session Gözlemcileri ─────────────────────────────────────────────
    #if !targetEnvironment(simulator)
    private var cancellables = Set<AnyCancellable>()

    private func observeSession(_ session: ObjectCaptureSession) {
        session.$userCompletedScanPass
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] passed in
                if passed { self?.maybeStartReconstruction() }
            }
            .store(in: &cancellables)

        session.$feedback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] feedback in
                self?.feedbackMessages = feedback.compactMap { Self.feedbackMessage(for: $0) }
            }
            .store(in: &cancellables)

        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionState in
                if case .failed(let error) = sessionState {
                    self?.state = .failed(error.localizedDescription)
                }
            }
            .store(in: &cancellables)
    }
    #endif

    // ─── Tarama Geçişini Tamamla ─────────────────────────────────────────
    func finishCapture() {
        #if !targetEnvironment(simulator)
        captureSession?.finish()
        maybeStartReconstruction()
        #endif
    }

    private func maybeStartReconstruction() {
        guard let imagesDir = imagesDirectory,
              let outputDir = outputDirectory else { return }
        state = .reconstructing
        Task {
            await reconstruct(imagesDirectory: imagesDir, outputDirectory: outputDir)
        }
    }

    // ─── Cihaz Üzerinde Fotogrametri (PhotogrammetrySession) ─────────────
    private func reconstruct(imagesDirectory: URL, outputDirectory: URL) async {
        #if targetEnvironment(simulator)
        await MainActor.run { self.state = .failed("Simulator'da fotogrametri desteklenmiyor.") }
        #else
        logger.info("PhotogrammetrySession başlatılıyor…")

        let usdzURL = outputDirectory.appendingPathComponent("snap3d_model.usdz")

        do {
            var config = PhotogrammetrySession.Configuration()
            config.sampleOrdering         = .unordered
            config.featureSensitivity     = .normal
            config.isObjectMaskingEnabled = true

            let session = try PhotogrammetrySession(
                input: imagesDirectory,
                configuration: config
            )

            let request = PhotogrammetrySession.Request.modelFile(
                url: usdzURL,
                detail: .medium
            )

            try session.process(requests: [request])

            for try await output in session.outputs {
                switch output {
                case .processingComplete:
                    logger.info("PhotogrammetrySession tamamlandı → \(usdzURL.path)")
                    await handleReconstructionComplete(usdzURL: usdzURL, outputDir: outputDirectory)

                case .requestProgress(_, let fraction):
                    await MainActor.run {
                        self.reconstructionProgress = Float(fraction)
                    }
                    logger.debug("İlerleme: \(Int(fraction * 100))%")

                case .requestError(_, let error):
                    throw error

                case .processingCancelled:
                    await MainActor.run { self.state = .failed("İşlem iptal edildi.") }

                default:
                    break
                }
            }

        } catch {
            logger.error("Fotogrametri hatası: \(error)")
            await MainActor.run {
                self.state = .failed("Model üretilemedi:\n\(error.localizedDescription)")
            }
        }
        #endif
    }

    // ─── Tamamlanma ─────────────────────────────────────────────────
    private func handleReconstructionComplete(usdzURL: URL, outputDir: URL) async {
        await MainActor.run {
            self.outputModelURL = usdzURL
            self.reconstructionProgress = 1.0
        }

        await MainActor.run {
            self.state = .completed
        }
        logger.info("✓ Model hazır: \(usdzURL.path)")
    }

    // ─── Sıfırla ─────────────────────────────────────────────────────────
    func reset() {
        #if !targetEnvironment(simulator)
        captureSession?.cancel()
        captureSession = nil
        cancellables.removeAll()
        #endif
        shotCount = 0
        feedbackMessages = []
        reconstructionProgress = 0
        outputModelURL = nil
        outputGLBURL = nil
        state = .ready
    }

    // ─── Feedback Mesajları ────────────────────────────────────────────────
    #if !targetEnvironment(simulator)
    private static func feedbackMessage(for feedback: ObjectCaptureSession.Feedback) -> String? {
        switch feedback {
        case .objectTooClose:           return "📏 Nesneye çok yakınsınız, biraz uzaklaşın"
        case .objectTooFar:             return "📏 Nesne çok uzak, yaklaşın"
        case .movingTooFast:            return "🐢 Daha yavaş hareket edin"
        case .environmentLowLight:      return "💡 Işık yetersiz"
        case .environmentTooDark:       return "🌙 Ortam çok karanlık"
        case .outOfFieldOfView:         return "👁 Nesne görüş alanı dışında"
        case .objectNotDetected:        return "🔍 Nesne tespit edilmedi"
        default:                        return nil
        }
    }
    #endif
}
