import AVFoundation
import Foundation

/// Streams ElevenLabs TTS audio and plays it as it arrives.
/// Uses the HTTP /stream endpoint plus an AVAssetResourceLoaderDelegate so
/// playback starts on the first ~32KB instead of waiting for the full file.
@MainActor
final class ElevenLabsTTS: NSObject {
    static let shared = ElevenLabsTTS()

    // Rachel — clean default. Make selectable when voice picking lands.
    private static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"
    private static let modelID = "eleven_flash_v2_5"

    private var player: AVPlayer?
    private var streamTask: Task<Void, Never>?
    private var loader: StreamingLoader?
    private var onFinish: (() -> Void)?
    private var endObserver: NSObjectProtocol?

    var isPlaying: Bool { player != nil }

    func speak(text: String, apiKey: String, onFinish: @escaping () -> Void) {
        stop()

        self.onFinish = onFinish
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(Self.defaultVoiceID)/stream?output_format=mp3_44100_128")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": Self.modelID,
        ])

        let loader = StreamingLoader()
        self.loader = loader
        let asset = AVURLAsset(url: URL(string: "stream://elevenlabs/audio.mp3")!)
        asset.resourceLoader.setDelegate(loader, queue: .global(qos: .userInitiated))
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }

        streamTask = Task.detached { [weak self, weak loader] in
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    await MainActor.run { self?.finish() }
                    return
                }
                for try await byte in bytes {
                    if Task.isCancelled { break }
                    loader?.append(byte)
                }
                loader?.markComplete()
            } catch {
                // Cancelled or network failure — finish quietly.
            }
            await MainActor.run { self?.finishIfNeverStarted() }
        }

        player.play()
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        loader = nil
        onFinish = nil
    }

    private func finish() {
        let cb = onFinish
        stop()
        cb?()
    }

    /// Stream failed before playback ever produced audio.
    private func finishIfNeverStarted() {
        guard let player, player.currentItem?.status != .readyToPlay else { return }
        finish()
    }

    /// Feeds the incoming byte stream to AVPlayer's resource loader.
    private final class StreamingLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
        private var buffer = Data()
        private var complete = false
        private var requests: [AVAssetResourceLoadingRequest] = []

        func append(_ byte: UInt8) {
            buffer.append(byte)
            pump()
        }

        func markComplete() {
            complete = true
            pump()
        }

        private func pump() {
            guard !requests.isEmpty else { return }
            // Hold back until we have a real buffer so the demuxer sees a
            // valid MP3 header on first read.
            guard buffer.count > 32 * 1024 || complete else { return }
            for req in requests {
                if let info = req.contentInformationRequest {
                    info.contentType = "public.mp3"
                    info.isByteRangeAccessSupported = false
                    if complete { info.contentLength = Int64(buffer.count) }
                }
                if let dataReq = req.dataRequest {
                    let offset = Int(dataReq.requestedOffset)
                    let available = buffer.count - offset
                    guard available > 0 else { continue }
                    let length = min(dataReq.requestedLength, available)
                    dataReq.respond(with: buffer.subdata(in: offset..<(offset + length)))
                }
                if complete {
                    req.finishLoading()
                }
            }
            if complete { requests.removeAll() }
        }

        func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                            shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            requests.append(loadingRequest)
            pump()
            return true
        }

        func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                            didCancel loadingRequest: AVAssetResourceLoadingRequest) {
            requests.removeAll { $0 === loadingRequest }
        }
    }
}
