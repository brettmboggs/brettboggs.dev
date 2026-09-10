// Gives the App Store preview its own soundtrack, rendered by the app.
//
// App Store Connect rejects a preview with no audio track, and this is an app
// about sound, so the answer is not a track of silence. Everything under
// Nightjar/Audio except AudioEngine.swift is plain Foundation, so the same
// renderer that feeds the phone's speaker can be run offline here, faster than
// real time, and the result muxed onto the video.
//
// It renders "Long Rain", which is the mix the preview shows on screen.
//
// It renders audio and nothing else. mux.swift lays it onto the video. They
// are two processes on purpose: the AAC encoder needs a running main run loop
// and AVAssetExportSession needs a blocked one, and a single process cannot
// give both.
//
//   swiftc -O -o mixdown main.swift <the Audio sources> SoundCatalog.swift
//   ./mixdown 28.0 preview-audio.m4a
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3, let seconds = Double(arguments[1]) else {
    print("usage: mixdown <seconds> <audio out .m4a>")
    exit(1)
}
let audioURL = URL(fileURLWithPath: arguments[2])

let sampleRate: Float = 48_000
let fadeSeconds = 1.5

/// The Long Rain preset, the same four numbers Mix.presets carries.
let voices: [(id: String, level: Float, tone: Float, motion: Float)] = [
    ("rain.light", 0.72, 0.42, 0.50),
    ("noise.brown", 0.30, 0.40, 0.50),
]

let renderer = Renderer(sampleRate: sampleRate)
for voice in voices {
    guard let slot = renderer.slot(for: voice.id) else {
        print("no slot for \(voice.id)")
        exit(1)
    }
    slot.texture.prepare(sampleRate: sampleRate, tone: voice.tone, motion: voice.motion)
    slot.targetGain = voice.level
    slot.currentGain = voice.level
}
renderer.setMasterGain(0.82, over: 0.001)

var finished = false

Task {
    do {
        let total = Int(Double(sampleRate) * seconds)

        // Rendered whole into memory. Twenty-eight seconds of stereo floats is
        // about ten megabytes, which is nothing here, and it means the renderer
        // is never asked for a partial block.
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        let block = 1024
        var offset = 0
        while offset < total {
            let n = min(block, total - offset)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    renderer.render(
                        frames: n,
                        left: l.baseAddress! + offset,
                        right: r.baseAddress! + offset,
                        stereo: true
                    )
                }
            }
            offset += n
        }

        // Ease in and out, so the preview does not start or stop on an edge.
        let fade = Int(Double(sampleRate) * fadeSeconds)
        for i in 0..<min(fade, total) {
            let g = Float(i) / Float(fade)
            left[i] *= g
            right[i] *= g
            left[total - 1 - i] *= g
            right[total - 1 - i] *= g
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buffer.frameLength = AVAudioFrameCount(total)
        for i in 0..<total {
            buffer.floatChannelData![0][i] = left[i]
            buffer.floatChannelData![1][i] = right[i]
        }

        // AAC rather than linear PCM: the video is muxed through passthrough,
        // so whatever this file holds ends up in the mp4, and twenty-eight
        // seconds of stereo float is ten megabytes of nothing.
        try? FileManager.default.removeItem(at: audioURL)
        let file = try AVAudioFile(forWriting: audioURL, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])
        try file.write(from: buffer)
        print("wrote \(audioURL.lastPathComponent)")
        finished = true
    } catch {
        print("failed: \(error)")
        exit(1)
    }
}

// The main thread pumps its run loop rather than blocking on a semaphore: the
// AAC encoder delivers its work through the main run loop, so parking the main
// thread deadlocks the process at nought percent CPU rather than failing.
while !finished {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
