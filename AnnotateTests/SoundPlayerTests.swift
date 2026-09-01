import XCTest

@testable import Annotate

@MainActor
final class SoundPlayerTests: XCTestCase {
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testPreloadsEachDistinctSoundOnce() {
        var loadCounts: [String: Int] = [:]
        var players: [String: SoundPlayingSpy] = [:]

        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { theme, sound in
            let resourceName = sound.resourceName(for: theme)
            loadCounts[resourceName, default: 0] += 1
            let player = SoundPlayingSpy()
            players[resourceName] = player
            return player
        }

        let distinctResourceNames = Set(
            SoundTheme.allCases.flatMap { theme in
                SoundPlayer.Sound.allCases.map { $0.resourceName(for: theme) }
            }
        )
        XCTAssertEqual(distinctResourceNames.count, 6)
        XCTAssertEqual(loadCounts.count, 6)
        XCTAssertTrue(loadCounts.values.allSatisfy { $0 == 1 })
        XCTAssertTrue(players.values.allSatisfy { $0.prepareCount == 1 })
        XCTAssertTrue(players.values.allSatisfy { $0.volume == soundEffectVolume })

        soundPlayer.playOverlayOn()
        soundPlayer.playOverlayOff()
        soundPlayer.playClearAll()

        XCTAssertTrue(loadCounts.values.allSatisfy { $0 == 1 })
    }

    func testEachActionPlaysOnlyItsClip() {
        let players = makePlayers()
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0]?[$1] }
        let chalk = players[.chalk]

        soundPlayer.playOverlayOn()
        XCTAssertEqual(chalk?[.overlayOn]?.playCount, 1)
        XCTAssertEqual(chalk?[.overlayOff]?.playCount, 0)
        XCTAssertEqual(chalk?[.clearAll]?.playCount, 0)

        soundPlayer.playOverlayOff()
        XCTAssertEqual(chalk?[.overlayOn]?.playCount, 1)
        XCTAssertEqual(chalk?[.overlayOff]?.playCount, 1)
        XCTAssertEqual(chalk?[.clearAll]?.playCount, 0)

        soundPlayer.playClearAll()
        XCTAssertEqual(chalk?[.overlayOn]?.playCount, 1)
        XCTAssertEqual(chalk?[.overlayOff]?.playCount, 1)
        XCTAssertEqual(chalk?[.clearAll]?.playCount, 1)
    }

    func testPlaybackFollowsSoundsEnabledSetting() {
        let players = makePlayers()
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0]?[$1] }
        let chalk = players[.chalk] ?? [:]

        testDefaults.soundsEnabled = false
        soundPlayer.playOverlayOn()
        soundPlayer.playOverlayOff()
        soundPlayer.playClearAll()

        XCTAssertTrue(chalk.values.allSatisfy { $0.playCount == 0 })

        testDefaults.soundsEnabled = true
        soundPlayer.playOverlayOn()
        soundPlayer.playOverlayOff()
        soundPlayer.playClearAll()

        XCTAssertTrue(chalk.values.allSatisfy { $0.playCount == 1 })
    }

    func testPlaybackUsesSelectedTheme() {
        let players = makePlayers()
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0]?[$1] }

        testDefaults.soundTheme = .paper
        soundPlayer.playOverlayOn()

        XCTAssertEqual(players[.paper]?[.overlayOn]?.playCount, 1)
        XCTAssertEqual(players[.chalk]?[.overlayOn]?.playCount, 0)

        testDefaults.soundTheme = .chalk
        soundPlayer.playOverlayOn()

        XCTAssertEqual(players[.chalk]?[.overlayOn]?.playCount, 1)
        XCTAssertEqual(players[.paper]?[.overlayOn]?.playCount, 1)
    }

    func testPlaybackRestartsLoadedClip() {
        let players = makePlayers()
        players[.chalk]?[.overlayOn]?.currentTime = 1
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0]?[$1] }

        soundPlayer.playOverlayOn()

        XCTAssertEqual(players[.chalk]?[.overlayOn]?.currentTime, 0)
    }

    func testBundledOverlaySoundAssetsLoad() {
        for theme in SoundTheme.allCases {
            for sound in SoundPlayer.Sound.allCases {
                let resourceName = sound.resourceName(for: theme)
                let url = SoundPlayer.resourceURL(for: sound, theme: theme)
                XCTAssertNotNil(url, "Missing \(resourceName).caf in the app bundle")
                XCTAssertNotNil(
                    SoundPlayer.makePlayer(for: sound, theme: theme),
                    "Failed to load \(resourceName).caf from \(url?.path ?? "nil")"
                )
            }
        }
    }

    private func makePlayers() -> [SoundTheme: [SoundPlayer.Sound: SoundPlayingSpy]] {
        Dictionary(
            uniqueKeysWithValues: SoundTheme.allCases.map { theme in
                let themePlayers = Dictionary(
                    uniqueKeysWithValues: SoundPlayer.Sound.allCases.map { ($0, SoundPlayingSpy()) }
                )
                return (theme, themePlayers)
            }
        )
    }
}

private final class SoundPlayingSpy: SoundPlaying {
    var currentTime: TimeInterval = 0
    var volume: Float = 1
    private(set) var prepareCount = 0
    private(set) var playCount = 0

    func prepareToPlay() -> Bool {
        prepareCount += 1
        return true
    }

    func play() -> Bool {
        playCount += 1
        return true
    }
}
