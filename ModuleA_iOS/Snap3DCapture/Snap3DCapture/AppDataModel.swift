// AppDataModel.swift
// Snap3D — Uygulama Durum Yöneticisi
//
// ObjectCaptureSession + PhotogrammetrySession'ı koordine eder.
// Cihaz üzerinde tüm 3D model üretimini yönetir — sunucu gerektirmez.

import Foundation
import RealityKit
import Combine
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.snap3d.capture", category: "AppDataModel")

@MainActor
final class AppDataModel: ObservableObject {

    // ─── Yayımlanan State ──────────────────────────────────────────────────
    @Published var state: AppState = .ready
    @Published var captureSession: ObjectCaptureSession?
    @Published var shotCount: Int = 0
    @Published var feedbackMessages: [String] = []
    @Published var reconstructionProgress: Float = 0.0
    @Published var outputModelURL: URL?
    @Published var outputGLBURL: URL?

    // ─── Oturum Dizinleri ─────────────────────────────────────────────────
    private var imagesDirectory: URL?
    private var checkpointDirectory: URL?
    private var outputDirectory: URL?

    // ─── Destekli Cihaz Kontrolü ──────────────────────────────────────────
    /// ObjectCaptureSession iOS 17+ ve A14 Bionic+ gerektirir
    static var isSupported: Bool {
        ObjectCaptureSession.isSupported
    }

    // ─── Yeni Tarama Başlat ───────────────────────────────────────────────
    func startCapture() {
        guard Self.isSupported else {
            state = .failed("Bu cihaz Object Capture'ı desteklemiyor.\niPhone 12 Pro veya üzeri gereklidir.")
            return
        }

        // Geçici dizinleri hazırla
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

        // ObjectCaptureSession oluştur
        let session = ObjectCaptureSession()
        captureSession = session
        shotCount = 0
        feedbackMessages = []

        // State değişikliklerini dinle
        observeSession(session)

        // Konfigürasyon: Checkpoint desteği + yüksek kalite
        var config = ObjectCaptureSession.Configuration()
        config.checkpointDirectory = checkpointDirectory
        config.isOverCaptureEnabled = true   // Aşırı yakalama = daha iyi kalite

        // Başlat
        session.start(imagesDirectory: imagesDirectory!, configuration: config)
        state = .capturing

        logger.info("ObjectCaptureSession başlatıldı → \(self.imagesDirectory!.path)")
    }

    // ─── Session Gözlemcileri ─────────────────────────────────────────────
    private var cancellables = Set<AnyCancellable>()

    private func observeSession(_ session: ObjectCaptureSession) {
        // Çekim sayısı
        session.$userCompletedScanPass
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] passed in
                if passed { self?.maybeStartReconstruction() }
            }
            .store(in: &cancellables)

        // Geri bildirim
        session.$feedback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] feedback in
                self?.feedbackMessages = feedback.compactMap { Self.feedbackMessage(for: $0) }
            }
            .store(in: &cancellables)

        // Hata
        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionState in
                if case .failed(let error) = sessionState {
                    self?.state = .failed(error.localizedDescription)
                }
            }
            .store(in: &cancellables)
    }

    // ─── Tarama Geçişini Tamamla ─────────────────────────────────────────
    func finishCapture() {
        captureSession?.finish()
        maybeStartReconstruction()
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
        logger.info("PhotogrammetrySession başlatılıyor…")

        // Çıktı USDZ dosyası
        let usdzURL = outputDirectory.appendingPathComponent("snap3d_model.usdz")

        do {
            var config = PhotogrammetrySession.Configuration()
            config.sampleOrdering         = .unordered
            config.featureSensitivity     = .normal
            config.isObjectMaskingEnabled = true   // Arka planı otomatik maskele

            let session = try PhotogrammetrySession(
                input: imagesDirectory,
                configuration: config
            )

            // İstek: Detail.medium → denge kalite/boyut
            // Ticaret için .full da kullanılabilir
            let request = PhotogrammetrySession.Request.modelFile(
                url: usdzURL,
                detail: .medium
            )

            try session.process(requests: [request])

            // Asenkron çıktıları işle
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
    }

    // ─── Tamamlanma: USDZ → Paylaşım ─────────────────────────────────────
    private func handleReconstructionComplete(usdzURL: URL, outputDir: URL) async {
        // USDZ kullanıma hazır
        await MainActor.run {
            self.outputModelURL = usdzURL
            self.reconstructionProgress = 1.0
        }

        // Opsiyonel: USDZ → GLB dönüşümü (ek Python/Blender server'a gönder)
        // Eğer web viewer için GLB gerekiyorsa:
        //   await convertToGLB(usdzURL: usdzURL, outputDir: outputDir)

        await MainActor.run {
            self.state = .completed
        }
        logger.info("✓ Model hazır: \(usdzURL.path)")
    }

    // ─── Sıfırla ─────────────────────────────────────────────────────────
    func reset() {
        captureSession?.cancel()
        captureSession = nil
        cancellables.removeAll()
        shotCount = 0
        feedbackMessages = []
        reconstructionProgress = 0
        outputModelURL = nil
        outputGLBURL = nil
        state = .ready
    }

    // ─── Feedback Mesajları ────────────────────────────────────────────────
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
}
