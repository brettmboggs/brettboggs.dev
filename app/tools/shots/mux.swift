// Puts an audio track onto a finished video without re-encoding either.
import AVFoundation
import Foundation

let video = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let audio = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[2]))
let output = URL(fileURLWithPath: CommandLine.arguments[3])
let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        let duration = try await video.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        let composition = AVMutableComposition()

        if let source = try await video.loadTracks(withMediaType: .video).first,
           let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: source, at: .zero)
            track.preferredTransform = try await source.load(.preferredTransform)
        }
        if let source = try await audio.loadTracks(withMediaType: .audio).first,
           let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audio.load(.duration)
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: min(duration, audioDuration)),
                of: source, at: .zero
            )
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print("no export session"); exit(1)
        }
        try? FileManager.default.removeItem(at: output)
        try await export.export(to: output, as: .mp4)
        print("wrote \(output.lastPathComponent)")
        semaphore.signal()
    } catch {
        print("failed: \(error)"); exit(1)
    }
}
semaphore.wait()
