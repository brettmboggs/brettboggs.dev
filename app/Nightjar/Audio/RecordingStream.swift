import AVFoundation
import Foundation

/// Streams one bundled recording, looping it forever without a seam.
///
/// The files are ten minutes of 44.1 kHz stereo each. Decoded to float that is
/// over 200 MB apiece, so nothing is held in memory: a reader thread decodes a
/// few seconds ahead into a ring buffer and the audio thread drains it.
///
/// Looping is crossfaded rather than butt-joined. Splicing the end of a
/// recording onto its start leaves a step in the waveform, and on broadband
/// noise a step is an audible tick every ten minutes, all night. The last two
/// seconds are faded out under the first two seconds fading in, which on noise
/// is completely inaudible.
final class RecordingStream {

    private let ring: AudioRingBuffer
    private let body: AVAudioFile
    private let head: AVAudioFile
    private let converter: AVAudioConverter
    private let inputBuffer: AVAudioPCMBuffer
    private let headBuffer: AVAudioPCMBuffer
    private let outputBuffer: AVAudioPCMBuffer

    private let totalFrames: AVAudioFramePosition
    private let crossfadeFrames: AVAudioFramePosition
    /// Where the plain body ends and the crossfade begins.
    private let bodyEnd: AVAudioFramePosition

    private var position: AVAudioFramePosition = 0
    private var headPosition: AVAudioFramePosition = 0

    private let inputChunk: AVAudioFrameCount = 8192
    private let outputChunk: AVAudioFrameCount = 8192

    init?(resource: String, outputFormat: AVAudioFormat, ring: AudioRingBuffer) {
        self.ring = ring
        guard let url = Bundle.main.url(forResource: resource, withExtension: "m4a") else {
            NSLog("Nightjar: recording '\(resource).m4a' is not in the bundle")
            return nil
        }
        do {
            body = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            head = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            NSLog("Nightjar: could not open '\(resource).m4a': \(error.localizedDescription)")
            return nil
        }

        let fileFormat = body.processingFormat
        totalFrames = body.length
        guard totalFrames > 4096 else {
            NSLog("Nightjar: '\(resource).m4a' is too short to loop")
            return nil
        }

        // Two seconds, or a quarter of the file if it is shorter than eight.
        let desired = AVAudioFramePosition(fileFormat.sampleRate * 2)
        crossfadeFrames = max(min(desired, totalFrames / 4), 1)
        bodyEnd = totalFrames - crossfadeFrames

        guard
            let conv = AVAudioConverter(from: fileFormat, to: outputFormat),
            let input = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: inputChunk),
            let headBuf = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: inputChunk),
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputChunk)
        else {
            NSLog("Nightjar: could not set up conversion for '\(resource).m4a'")
            return nil
        }
        converter = conv
        inputBuffer = input
        headBuffer = headBuf
        outputBuffer = output
    }

    // MARK: - Reader thread

    /// Tops the ring up. Safe to call as often as you like; it returns as soon
    /// as the buffer is full.
    func refill() {
        while ring.availableToWrite >= Int(outputChunk) {
            outputBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                let produced = self.fillInput()
                guard produced > 0 else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                return self.inputBuffer
            }

            if status == .error {
                NSLog("Nightjar: conversion failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let frames = Int(outputBuffer.frameLength)
            guard frames > 0, let channels = outputBuffer.floatChannelData else { return }
            let left = channels[0]
            let right = outputBuffer.format.channelCount > 1 ? channels[1] : channels[0]
            ring.write(left: left, right: right, frames: frames)

            if status == .inputRanDry && frames == 0 { return }
        }
    }

    /// Fills `inputBuffer` with the next stretch of the looped recording, in the
    /// file's own format. Chunks never straddle the crossfade boundary, so each
    /// one is either plain body or entirely inside the fade.
    private func fillInput() -> Int {
        // Two passes: if the first ends exactly on the loop point it wraps and
        // the second actually reads, so a wrap never costs a refill cycle.
        for _ in 0..<2 {
            if position < bodyEnd {
                let wanted = min(AVAudioFramePosition(inputChunk), bodyEnd - position)
                let read = readBody(frames: AVAudioFrameCount(wanted))
                guard read > 0 else {
                    wrap()
                    continue
                }
                position += AVAudioFramePosition(read)
                return read
            }

            // Inside the crossfade: the tail fades out under the head.
            let wanted = min(AVAudioFramePosition(inputChunk), totalFrames - position)
            guard wanted > 0 else {
                wrap()
                continue
            }
            let read = readBody(frames: AVAudioFrameCount(wanted))
            guard read > 0 else {
                wrap()
                continue
            }
            let headRead = readHead(frames: AVAudioFrameCount(read))
            blend(frames: min(read, headRead))

            position += AVAudioFramePosition(read)
            headPosition += AVAudioFramePosition(headRead)
            if position >= totalFrames { wrap() }
            return read
        }
        return 0
    }

    private func readBody(frames: AVAudioFrameCount) -> Int {
        do {
            if body.framePosition != position { body.framePosition = position }
            try body.read(into: inputBuffer, frameCount: frames)
            return Int(inputBuffer.frameLength)
        } catch {
            NSLog("Nightjar: read failed: \(error.localizedDescription)")
            return 0
        }
    }

    private func readHead(frames: AVAudioFrameCount) -> Int {
        do {
            if head.framePosition != headPosition { head.framePosition = headPosition }
            try head.read(into: headBuffer, frameCount: frames)
            return Int(headBuffer.frameLength)
        } catch {
            return 0
        }
    }

    /// Equal-power crossfade, so the summed power stays flat through the join.
    private func blend(frames: Int) {
        guard
            frames > 0,
            let tail = inputBuffer.floatChannelData,
            let start = headBuffer.floatChannelData
        else { return }

        let channels = Int(inputBuffer.format.channelCount)
        let span = Float(crossfadeFrames)
        for channel in 0..<channels {
            let out = tail[channel]
            let incoming = start[channel]
            for i in 0..<frames {
                let t = Float(headPosition + AVAudioFramePosition(i)) / span
                let phase = min(max(t, 0), 1) * .pi / 2
                out[i] = out[i] * cosf(phase) + incoming[i] * sinf(phase)
            }
        }
    }

    /// After the first pass the loop runs from the end of the crossfade, since
    /// the head has already been played underneath the tail.
    private func wrap() {
        position = crossfadeFrames
        headPosition = 0
    }
}

/// One background queue services every active recording.
///
/// A single timer waking a few times a second beats a thread per sound, which
/// matters when this runs for eight hours on battery.
final class RecordingStreamPool {
    static let shared = RecordingStreamPool()

    private let queue = DispatchQueue(
        label: "dev.brettboggs.nightjar.recordings",
        qos: .userInitiated
    )
    private var timer: DispatchSourceTimer?
    private var streams: [ObjectIdentifier: RecordingStream] = [:]

    private init() {}

    func add(_ stream: RecordingStream) {
        queue.async {
            self.streams[ObjectIdentifier(stream)] = stream
            // Fill immediately so the voice has audio before its gain ramps up.
            stream.refill()
            self.startTimerIfNeeded()
        }
    }

    func remove(_ stream: RecordingStream) {
        queue.async {
            self.streams.removeValue(forKey: ObjectIdentifier(stream))
            if self.streams.isEmpty {
                self.timer?.cancel()
                self.timer = nil
            }
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        // The ring holds two seconds; refilling every 400 ms leaves ample
        // headroom for scheduling jitter.
        source.schedule(deadline: .now() + 0.4, repeating: 0.4, leeway: .milliseconds(120))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            for stream in self.streams.values {
                stream.refill()
            }
        }
        source.resume()
        timer = source
    }
}
