import AVFoundation

protocol SoundPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }

    @discardableResult
    func prepareToPlay() -> Bool

    @discardableResult
    func play() -> Bool
}

extension AVAudioPlayer: SoundPlaying {}

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

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
    }

    private let userDefaults: UserDefaults
    private let players: [Sound: SoundPlaying]

    private convenience init() {
        self.init(userDefaults: .standard) { sound in
            Self.makePlayer(for: sound)
        }
    }

    init(userDefaults: UserDefaults, makePlayer: (Sound) -> SoundPlaying?) {
        self.userDefaults = userDefaults

        var loadedPlayers: [Sound: SoundPlaying] = [:]
        loadedPlayers.reserveCapacity(Sound.allCases.count)
        for sound in Sound.allCases {
            guard let player = makePlayer(sound) else {
                continue
            }
            player.volume = 0.2
            player.prepareToPlay()
            loadedPlayers[sound] = player
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

    private static func makePlayer(for sound: Sound) -> SoundPlaying? {
        guard let url = Bundle.main.url(forResource: sound.resourceName, withExtension: "caf"),
            let player = try? AVAudioPlayer(contentsOf: url)
        else {
            return nil
        }

        return player
    }

    private func play(_ sound: Sound) {
        guard userDefaults.soundsEnabled, let player = players[sound] else {
            return
        }

        player.currentTime = 0
        player.play()
    }
}
