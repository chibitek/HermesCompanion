import SwiftUI
import AVFoundation

// MARK: - Audio Level Monitor

/// Monitors the microphone input level via AVAudioEngine and publishes
/// normalized amplitude values for the visualizer.
@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published var levels: [Float] = Array(repeating: 0.0, count: 28)
    @Published var isMonitoring = false

    private let audioEngine = AVAudioEngine()
    private var monitorTimer: Timer?

    /// Starts monitoring the microphone. Called when the voice page appears.
    /// Uses a lightweight tap on the input node to compute per-band RMS.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // If we can't get the mic, fall back to idle animation
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processBuffer(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            // If the engine can't start (e.g. sim without mic), use fake levels
            startFakeLevels()
        }
    }

    /// Stops monitoring and releases the audio tap.
    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        monitorTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    // MARK: - Private

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Split the buffer into `levels.count` bands and compute RMS per band
        let bandSize = max(frameLength / levels.count, 1)
        var newLevels: [Float] = []

        for i in 0..<levels.count {
            let start = i * bandSize
            let end = min(start + bandSize, frameLength)
            guard start < end else {
                newLevels.append(0)
                continue
            }

            var sum: Float = 0
            for j in start..<end {
                let sample = channelData[j]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(end - start))
            // Normalize: 0..1 with some gain
            let normalized = min(rms * 5.0, 1.0)
            newLevels.append(normalized)
        }

        Task { @MainActor [weak self] in
            self?.levels = newLevels
        }
    }

    /// Fallback: generates fake but organic-looking levels for the simulator
    /// when the mic isn't available.
    private func startFakeLevels() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var newLevels: [Float] = []
                for i in 0..<self.levels.count {
                    let base = Float(0.15 + 0.25 * sin(Date().timeIntervalSinceReferenceDate * 3 + Double(i) * 0.3))
                    let noise = Float.random(in: 0...0.15)
                    let env = Float(1.0 - abs(Double(i) - Double(self.levels.count) / 2.0) / Double(self.levels.count))
                    newLevels.append(max(0, min(1, base + noise) * env))
                }
                self.levels = newLevels
            }
        }
    }
}

// MARK: - Equalizer Visualizer

/// Equalizer-style audio visualizer: vertical bars that react to mic input.
/// When the monitor is active, bars reflect real audio levels. When idle,
/// bars animate gently.
struct AudioVisualizer: View {
    var levels: [Float]
    var preset: CyberpunkVoicePreset
    var isActive: Bool
    var isSpeaking: Bool = false

    private let barCount = 28
    private let barSpacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let barWidth = (geo.size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)
            let maxHeight = geo.size.height

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    EqualizerBar(
                        index: i,
                        level: CGFloat(displayLevel(for: i)),
                        maxHeight: maxHeight,
                        barWidth: barWidth,
                        color: i % 3 == 2 ? preset.secondary : preset.primary,
                        isActive: isActive,
                        isSpeaking: isSpeaking
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func displayLevel(for index: Int) -> Float {
        if levels.count > index && levels[index] > 0 {
            return levels[index]
        }
        // Fallback idle animation value
        let t = Date().timeIntervalSinceReferenceDate
        let phase = Double(index) * 0.35
        if isActive {
            return Float(0.2 + 0.3 * abs(sin(t * 4 + phase)))
        } else if isSpeaking {
            return Float(0.1 + 0.5 * abs(sin(t * 8 + phase)))
        } else {
            return Float(0.05 + 0.03 * abs(sin(t * 1.5 + phase)))
        }
    }
}

// MARK: - Single Bar

struct EqualizerBar: View {
    let index: Int
    let level: CGFloat
    let maxHeight: CGFloat
    let barWidth: CGFloat
    let color: Color
    let isActive: Bool
    let isSpeaking: Bool

    @State private var animatedLevel: CGFloat = 0.05

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: barWidth, height: max(maxHeight * animatedLevel, 2))
            .frame(maxHeight: maxHeight, alignment: .bottom)
            .crtGlow(color, radius: 4, opacity: 0.6)
            .onAppear { animateBar() }
            .onChange(of: level) { _, newLevel in
                withAnimation(.easeOut(duration: isSpeaking ? 0.08 : 0.12)) {
                    animatedLevel = newLevel
                }
            }
    }

    private func animateBar() {
        animatedLevel = level
    }
}
