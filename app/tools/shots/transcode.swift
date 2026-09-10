// Turns a simulator recording into an App Store app preview.
//
// Apple wants 886 x 1920 portrait for the 6.9 inch size, 15 to 30 seconds,
// H.264 or HEVC. A simulator records at the device's own 1320 x 2868 and at
// whatever frame rate it feels like, so this rescales, pins the frame rate,
// and trims to length.
import AVFoundation
import Foundation

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let seconds = Double(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "28") ?? 28

let target = CGSize(width: 886, height: 1920)
let asset = AVURLAsset(url: source)
let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            print("no video track"); exit(1)
        }
        let natural = try await track.load(.naturalSize)

        // Fill the width and centre what spills over the height. The overspill
        // is about five pixels, which is nothing, and letterboxing a preview
        // looks like a mistake.
        let scale = target.width / natural.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(
                translationX: 0,
                y: (target.height - natural.height * scale) / 2
            ))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)

        let duration = min(try await asset.load(.duration), CMTime(seconds: seconds, preferredTimescale: 600))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = target
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            print("no export session"); exit(1)
        }
        export.videoComposition = composition
        export.timeRange = CMTimeRange(start: .zero, duration: duration)
        try? FileManager.default.removeItem(at: output)
        try await export.export(to: output, as: .mp4)
        print("wrote \(output.lastPathComponent)")
        semaphore.signal()
    } catch {
        print("failed: \(error)")
        exit(1)
    }
}
semaphore.wait()
