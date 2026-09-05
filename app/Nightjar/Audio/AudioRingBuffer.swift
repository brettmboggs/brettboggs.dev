import Foundation

/// Single-producer, single-consumer stereo float ring buffer.
///
/// The reader thread decodes ahead into this; the audio thread drains it a
/// frame at a time. Each side only ever writes its own index and only ever
/// reads the other's, which is the one case where plain word-sized loads and
/// stores are safe without atomics on the hardware this ships to. The audio
/// thread never blocks and never allocates.
final class AudioRingBuffer {
    private let capacity: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>

    /// Monotonic frame counters. At 48 kHz an Int takes six million years to
    /// overflow, so they are never wrapped, only masked for addressing.
    private var writeIndex: Int = 0
    private var readIndex: Int = 0

    /// Counts frames the audio thread wanted but did not have. Non-zero means
    /// the reader is not keeping up.
    private(set) var underruns: Int = 0

    init(frames: Int) {
        // Round up to a power of two so addressing is a mask, not a modulo.
        var size = 1
        while size < max(frames, 2) { size <<= 1 }
        capacity = size

        left = UnsafeMutablePointer<Float>.allocate(capacity: size)
        right = UnsafeMutablePointer<Float>.allocate(capacity: size)
        left.initialize(repeating: 0, count: size)
        right.initialize(repeating: 0, count: size)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    var availableToRead: Int { writeIndex - readIndex }
    var availableToWrite: Int { capacity - (writeIndex - readIndex) }

    /// Producer side. Returns the number of frames actually written.
    @discardableResult
    func write(
        left source: UnsafePointer<Float>,
        right sourceRight: UnsafePointer<Float>,
        frames: Int
    ) -> Int {
        let count = min(frames, availableToWrite)
        guard count > 0 else { return 0 }
        let mask = capacity - 1
        var index = writeIndex
        for i in 0..<count {
            let slot = index & mask
            left[slot] = source[i]
            right[slot] = sourceRight[i]
            index += 1
        }
        writeIndex = index
        return count
    }

    /// Consumer side, called from the audio thread. Silence on underrun: at the
    /// gains this runs at, a dropped frame is inaudible and a click is not.
    @inline(__always)
    func readFrame() -> (Float, Float) {
        guard readIndex < writeIndex else {
            underruns &+= 1
            return (0, 0)
        }
        let slot = readIndex & (capacity - 1)
        readIndex += 1
        return (left[slot], right[slot])
    }

    /// Producer side only, and only while the consumer is stopped.
    func reset() {
        readIndex = 0
        writeIndex = 0
        underruns = 0
    }
}
