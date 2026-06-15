import AVFoundation
import Foundation

public enum LocalAudioFileWriter {
    public static func writePCMToM4A(
        samples: [Float],
        outputURL: URL,
        sampleRate: Double = Double(KokoroSynthesisConfig.sampleRate)
    ) throws {
        let parentDirectory = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try FileManager.default.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let tempPCMURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
        if FileManager.default.fileExists(atPath: tempPCMURL.path) {
            try FileManager.default.removeItem(at: tempPCMURL)
        }

        let pcmFile = try AVAudioFile(forWriting: tempPCMURL, settings: pcmFormat.settings)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw LocalKokoroError.cacheWriteFailed
        }
        buffer.frameLength = buffer.frameCapacity
        let destination = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { sourceBuffer in
            guard let sourceAddress = sourceBuffer.baseAddress else { return }
            let byteCount = sourceBuffer.count * MemoryLayout<Float>.stride
            destination.update(
                from: sourceAddress,
                count: sourceBuffer.count
            )
        }
        try pcmFile.write(from: buffer)

        let asset = AVURLAsset(url: tempPCMURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw LocalKokoroError.cacheWriteFailed
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?
        exportSession.exportAsynchronously {
            if exportSession.status != .completed {
                exportError = exportSession.error ?? LocalKokoroError.cacheWriteFailed
            }
            semaphore.signal()
        }
        semaphore.wait()
        try? FileManager.default.removeItem(at: tempPCMURL)
        if let exportError {
            throw exportError
        }
    }

    public static func silenceSamples(seconds: Double) -> [Float] {
        let sampleCount = Int(seconds * Double(KokoroSynthesisConfig.sampleRate))
        return Array(repeating: 0, count: max(sampleCount, 0))
    }
}
