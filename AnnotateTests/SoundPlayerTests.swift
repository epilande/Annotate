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
        var loadCounts: [SoundPlayer.Sound: Int] = [:]
        var players: [SoundPlayer.Sound: SoundPlayingSpy] = [:]

        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { sound in
            loadCounts[sound, default: 0] += 1
            let player = SoundPlayingSpy()
            players[sound] = player
            return player
        }

        XCTAssertEqual(Set(SoundPlayer.Sound.allCases.map(\.resourceName)).count, 3)
        XCTAssertEqual(loadCounts.count, 3)
        XCTAssertTrue(loadCounts.values.allSatisfy { $0 == 1 })
        XCTAssertTrue(players.values.allSatisfy { $0.prepareCount == 1 })
        XCTAssertTrue(players.values.allSatisfy { $0.volume == 0.2 })

        soundPlayer.playOverlayOn()
        soundPlayer.playOverlayOff()
        soundPlayer.playClearAll()

        XCTAssertTrue(loadCounts.values.allSatisfy { $0 == 1 })
    }

    func testEachActionPlaysOnlyItsClip() {
        let players = makePlayers()
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0] }

        soundPlayer.playOverlayOn()
        XCTAssertEqual(players[.overlayOn]?.playCount, 1)
        XCTAssertEqual(players[.overlayOff]?.playCount, 0)
        XCTAssertEqual(players[.clearAll]?.playCount, 0)

        soundPlayer.playOverlayOff()
        XCTAssertEqual(players[.overlayOn]?.playCount, 1)
        XCTAssertEqual(players[.overlayOff]?.playCount, 1)
        XCTAssertEqual(players[.clearAll]?.playCount, 0)

        soundPlayer.playClearAll()
        XCTAssertEqual(players[.overlayOn]?.playCount, 1)
        XCTAssertEqual(players[.overlayOff]?.playCount, 1)
        XCTAssertEqual(players[.clearAll]?.playCount, 1)
    }

    func testPlaybackFollowsSoundsEnabledSetting() {
        let players = makePlayers()
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0] }

        testDefaults.soundsEnabled = false
        soundPlayer.playOverlayOn()
        soundPlayer.playOverlayOff()
        soundPlayer.playClearAll()

        XCTAssertTrue(players.values.allSatisfy { $0.playCount == 0 })

        testDefaults.soundsEnabled = true
        soundPlayer.playOverlayOn()
        soundPlayer.playOverlayOff()
        soundPlayer.playClearAll()

        XCTAssertTrue(players.values.allSatisfy { $0.playCount == 1 })
    }

    func testPlaybackRestartsLoadedClip() {
        let players = makePlayers()
        players[.overlayOn]?.currentTime = 1
        let soundPlayer = SoundPlayer(userDefaults: testDefaults) { players[$0] }

        soundPlayer.playOverlayOn()

        XCTAssertEqual(players[.overlayOn]?.currentTime, 0)
    }

    private func makePlayers() -> [SoundPlayer.Sound: SoundPlayingSpy] {
        Dictionary(
            uniqueKeysWithValues: SoundPlayer.Sound.allCases.map { ($0, SoundPlayingSpy()) }
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
