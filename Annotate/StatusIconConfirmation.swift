import AppKit

/// What the menu bar says about a capture that reached a destination: a checkmark in the
/// status item, and this announcement for VoiceOver.
enum CaptureConfirmation: String, Equatable {
    case saved = "Capture saved"
    case copied = "Capture copied"

    /// Saved when the image has a file, else copied when it is on the clipboard. Nil when it
    /// went nowhere, which the capture reports as a failure instead.
    init?(_ result: CaptureResult) {
        if result.savedFile != nil {
            self = .saved
        } else if result.copiedToClipboard {
            self = .copied
        } else {
            return nil
        }
    }

    var announcement: String { rawValue }
}

/// How long the status item shows its checkmark after a capture. Each capture starts the time
/// over, and the end always hands the icon back through `onChange`, so the regular icon comes
/// back drawn from the app's state at that moment, never from a copy taken before.
@MainActor
final class StatusIconConfirmation {
    /// Runs `action` after `delay`. Tests substitute one that holds the actions to run by hand.
    typealias Schedule = @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void

    /// A main run loop timer in the common modes, so it fires while the status menu is open,
    /// and in a run loop nested inside a main-queue job, where the main queue itself waits.
    static let runLoopTimer: Schedule = { delay, action in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    var duration: TimeInterval
    private(set) var isShowing = false
    /// How expiries run. Tests set one that holds them to run by hand.
    var schedule: Schedule
    private let onChange: @MainActor () -> Void
    /// Counts every show and end, so only the latest show's expiry ends the checkmark.
    private var generation = 0

    /// `onChange` runs when the checkmark goes up and again when it comes down.
    init(
        duration: TimeInterval = 1.5,
        schedule: @escaping Schedule = StatusIconConfirmation.runLoopTimer,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.duration = duration
        self.schedule = schedule
        self.onChange = onChange
    }

    /// Shows the checkmark for `duration` from now, however long it has been up already.
    func show() {
        generation += 1
        let shown = generation
        schedule(duration) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.end()
        }
        guard !isShowing else { return }
        isShowing = true
        onChange()
    }

    /// Takes the checkmark down now, and keeps any pending expiry from doing anything.
    func end() {
        generation += 1
        guard isShowing else { return }
        isShowing = false
        onChange()
    }
}
