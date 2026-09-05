import AVFoundation
import os

protocol SoundPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }

    @discardableResult
    func prepareToPlay() -> Bool

    @discardableResult
    func play() -> Bool
}

extension AVAudioPlayer: SoundPlaying {}

/// Selectable palette of feedback clips. Each theme ships a full set of sounds, prefixed with the
/// theme's raw value (for example `chalk-overlay-on.caf`).
enum SoundTheme: String, CaseIterable, Identifiable {
    case chalk
    case paper
    case marker
    case pencil
    case typewriter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chalk:
            return "Chalk"
        case .paper:
            return "Paper"
        case .marker:
            return "Marker"
        case .pencil:
            return "Pencil"
        case .typewriter:
            return "Typewriter"
        }
    }
}

@MainActor
final class SoundPlayer {
    static var shared = SoundPlayer()

    static func preload() {
        _ = shared
    }

    enum Sound: CaseIterable, Hashable {
        case overlayOn
        case overlayOff
        case clearAll

        var resourceName: String {
            switch self {
            case .overlayOn:
                return "overlay-on"
            case .overlayOff:
                return "overlay-off"
            case .clearAll:
                return "clear-all"
            }
        }

        /// The bundled file name for this clip in a given theme, without the extension.
        func resourceName(for theme: SoundTheme) -> String {
            "\(theme.rawValue)-\(resourceName)"
        }
    }

    private let userDefaults: UserDefaults
    private let players: [SoundTheme: [Sound: SoundPlaying]]

    private convenience init() {
        self.init(userDefaults: .standard) { theme, sound in
            Self.makePlayer(for: sound, theme: theme)
        }
    }

    init(userDefaults: UserDefaults, makePlayer: (SoundTheme, Sound) -> SoundPlaying?) {
        self.userDefaults = userDefaults

        var loadedPlayers: [SoundTheme: [Sound: SoundPlaying]] = [:]
        loadedPlayers.reserveCapacity(SoundTheme.allCases.count)
        for theme in SoundTheme.allCases {
            var themePlayers: [Sound: SoundPlaying] = [:]
            themePlayers.reserveCapacity(Sound.allCases.count)
            for sound in Sound.allCases {
                guard let player = makePlayer(theme, sound) else {
                    continue
                }
                player.volume = soundEffectVolume
                player.prepareToPlay()
                themePlayers[sound] = player
            }
            loadedPlayers[theme] = themePlayers
        }
        players = loadedPlayers
    }

    func playOverlayOn() {
        play(.overlayOn)
    }

    func playOverlayOff() {
        play(.overlayOff)
    }

    func playClearAll() {
        play(.clearAll)
    }

    static func resourceURL(for sound: Sound, theme: SoundTheme) -> URL? {
        let resourceName = sound.resourceName(for: theme)
        for bundle in resourceBundles {
            if let url = bundle.url(forResource: resourceName, withExtension: "caf") {
                return url
            }
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: "caf",
                subdirectory: "Sounds"
            ) {
                return url
            }
        }
        return nil
    }

    static func makePlayer(for sound: Sound, theme: SoundTheme) -> SoundPlaying? {
        guard let url = resourceURL(for: sound, theme: theme) else {
            reportLoadFailure(for: sound, theme: theme, reason: "resource not found in bundle")
            return nil
        }

        do {
            return try AVAudioPlayer(contentsOf: url)
        } catch {
            reportLoadFailure(for: sound, theme: theme, reason: error.localizedDescription)
            return nil
        }
    }

    private static var resourceBundles: [Bundle] {
        #if SWIFT_PACKAGE
        [Bundle.module, Bundle(for: SoundPlayer.self), Bundle.main]
        #else
        [Bundle(for: SoundPlayer.self), Bundle.main]
        #endif
    }

    private static let log = Logger(subsystem: "com.epilande.Annotate", category: "SoundPlayer")

    /// Logs rather than traps: a missing clip degrades to silence, and a bundling regression should
    /// surface as a failing test or a Console line, never as a crash at launch.
    private static func reportLoadFailure(for sound: Sound, theme: SoundTheme, reason: String) {
        log.error(
            "Failed to load \(sound.resourceName(for: theme), privacy: .public).caf: \(reason, privacy: .public)"
        )
    }

    /// Reads the theme at call time so a Settings change takes effect without a reload.
    private func play(_ sound: Sound) {
        guard userDefaults.soundsEnabled,
            let player = players[userDefaults.soundTheme]?[sound]
        else {
            return
        }

        player.currentTime = 0
        player.play()
    }
}
