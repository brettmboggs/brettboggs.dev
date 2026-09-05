import Foundation
import MediaPlayer
import UIKit

/// Lock Screen and Control Center transport.
///
/// There is no track here, so the metadata is bent slightly: when a sleep timer
/// is running it is reported as a finite "track" whose duration is the timer,
/// which makes the Lock Screen show a real countdown to when the sound stops.
final class NowPlayingCenter {

    private var artworkCache: MPMediaItemArtwork?
    private var isConfigured = false

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onNextMix: (() -> Void)?
    var onPreviousMix: (() -> Void)?

    func configureCommands() {
        guard !isConfigured else { return }
        isConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.onStop?()
            return .success
        }
        // Skipping moves through saved mixes, which is the only "next" that
        // means anything in an app with no tracks.
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextMix?()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousMix?()
            return .success
        }

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.changePlaybackPositionCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
    }

    func update(
        mixName: String,
        subtitle: String,
        isPlaying: Bool,
        timerStart: Date?,
        timerEnd: Date?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: mixName,
            MPMediaItemPropertyArtist: subtitle.isEmpty ? "Nightjar" : subtitle,
            MPMediaItemPropertyAlbumTitle: "Nightjar",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]

        if let start = timerStart, let end = timerEnd, end > start {
            let duration = end.timeIntervalSince(start)
            let elapsed = min(max(Date().timeIntervalSince(start), 0), duration)
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }

        if let artwork = artwork() {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Drawn once rather than shipped as an asset, so it always matches the
    /// palette and costs nothing in the bundle.
    private func artwork() -> MPMediaItemArtwork? {
        if let cached = artworkCache { return cached }
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 1).cgColor,
                UIColor(red: 0.24, green: 0.15, blue: 0.08, alpha: 1).cgColor,
                UIColor(red: 0.55, green: 0.33, blue: 0.15, alpha: 1).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.62, 1]
            ) else { return }
            cg.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.78),
                startRadius: 0,
                endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.78),
                endRadius: size.width * 0.85,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        let artwork = MPMediaItemArtwork(boundsSize: size) { _ in image }
        artworkCache = artwork
        return artwork
    }
}
