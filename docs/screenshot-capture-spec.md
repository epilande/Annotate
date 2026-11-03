# Screenshot capture (#80): design spec

Status: approved 2026-11-01, with the open questions settled under Decisions. Written against `main` at `8b0d70b` (v1.8.0 plus #135 to #140).

## Verdict and scope

Capture fits Annotate. It closes the "annotate, capture, share" loop the issue describes, and three quarters of the plumbing exists: `ScreenSampler` already takes ScreenCaptureKit screenshots of one display with Annotate's windows excluded, the command layer runs the same code from menus, Shortcuts, and `annotate://`, and every annotation already carries a monotonic creation time.

**v1 ships:** Capture Screen and Capture Area for one display, PNG to a folder, a copy on the clipboard, an on-overlay confirmation plus a system notification with Show in Finder, a Capture pane in Settings (folder, after-capture destination, notification, Screen Recording status for Capture and Redact), both commands in Shortcuts and `annotate://`, and an opt-in JSON sidecar.

**Waits:** window crop, stitching several displays, global hotkeys for capture, sidecar on by default, session recording and bundles, and opening an image to annotate.

## Answers 1 to 9

**1. Fit and smallest good v1.** As above. The one piece of scope that looks optional but is not: freezing fade while the area picker is up. Fade Mode is the default with a 0.625 s hold, so without a freeze, Capture Area in the default mode saves an empty region. Naming: "Capture Screen" and "Capture Area" rather than the issue's "Save Full Screen Screenshot", so the menu, shortcut, intent, and link share one short vocabulary.

**2. Capturing screen plus annotations.** Take the ScreenCaptureKit screenshot of the display with Annotate excluded (what `ScreenSampler.capture` does today), then composite in process: board fill at its opacity if the board is on, then the annotations rendered from `OverlayDocument` into a `CGContext` at the snapshot's pixel scale. Not "capture our own window too": the HUD pill, quick picker, selection chrome, and the text field are all subviews of `overlayView`, so any capture that includes the window leaks chrome, and fade alpha becomes whatever the compositor had that frame. The composite path needs a new `AnnotationRenderer` extracted from `OverlayView`'s private draw primitives, which `OverlayView.draw` then calls. That extraction is the main engineering cost and the main seam for everything later.

- Permission: reuse the cached `CGPreflightScreenCaptureAccess` state. Never prompt from the overlay, since the prompt lands under it. When access is missing, the capture command shows a HUD ("Screen Recording is off. Opening Settings…"), closes the interactive overlay, and opens Settings to the Capture pane, which asks the way the Redact row does today. That row moves out of the Tools pane (`ToolsSettingsView`) into the Capture pane, so Screen Recording status lives in one place, and the Redact section points there. Annotations persist across the close. One useful fallback: when the board is on at opacity 1.0 the screen pixels are fully covered, so capture skips ScreenCaptureKit and works without permission. Update `NSScreenCaptureUsageDescription`, which mentions only Pixelate and Blur.
- Retina: composite at the snapshot's native pixel size (`pointPixelScale`), scale the context by `snapshot.scale`, and write PNG DPI metadata of 72 times scale, matching `screencapture`.
- Which display: the screen of the key interactive overlay, else the display under the pointer (`getCurrentScreen()`), else `NSScreen.main`. Annotations are drawn only when that display's overlay is visible, interactive or Always-On. A link capture with the overlay hidden saves the plain screen, which is what is on screen. One display per capture. In Fade Mode a full-screen capture draws each annotation at its current fade, as shown on screen.
- Streaming later: `SCStream` uses the same `SCContentFilter` and configuration as `SCScreenshotManager`, so put the filter builder behind a `DisplayCapturing` protocol with `captureDisplay` now and room for a frame stream later. The renderer draws a document value into any `CGContext`, so a frame pipeline can reuse it unchanged.

**3. Selected area.** #111 is a detector for the system's screenshot UI, not a picker, and the Select tool's marquee is tool state threaded through `OverlayWindow.mouseDown` and `mouseUp`. Reusing either would entangle capture with the Select tool. Build a small AppKit-only `RegionPicker` view that the overlay window installs over `overlayView` while picking, like the quick picker: crosshair, dimmed outside, size label, release to capture, Escape to cancel, no dependency on `OverlayView` or `OverlayDocument`. When Capture Area runs from a link, an intent, or the menu with no interactive overlay open, including in Always-On where overlays ignore the mouse, it opens the interactive overlay the way `showInteractiveOverlay` does and then shows the picker. The picker reports a rect in display-local points, which the capture crops using the existing `ScreenSampler.pixelRect` math. Window crop waits, but `CaptureRegion` is an enum (`.display`, `.rect`) so `.window(CGWindowID)` is a new case, not a redesign.

**4. Output.** Always write the file. Settings offers "After capture: Save to folder, Copy to clipboard, Both", default Both: the file is saved and the image is also copied to the clipboard. File name `Annotate 2026-11-01 at 10.23.45.png`, mirroring macOS, with " (2)" on collision. Default folder `~/Pictures/Annotate` through `com.apple.security.assets.pictures.read-write`; Pictures has no first-access TCC prompt, while Desktop, Documents, and Downloads do, and that prompt would land under the overlay. Custom folder: switch the current `files.user-selected.read-only` entitlement to `read-write`, pick with `NSOpenPanel`, store a security-scoped bookmark as a `SettingKey<Data>`, resolve per save inside `startAccessingSecurityScopedResource`, and fall back to the default with a HUD when the bookmark is stale. Notification: the HUD pill always shows the file name on the overlay; a `UNUserNotificationCenter` notification with a thumbnail and a Show in Finder action is sent when authorized. Authorization is requested from the Capture pane only, same rule as Screen Recording. Notifications go behind a small protocol with a test stub, like `RedactionSampling`. Sidecar: ship the JSON format and writer in v1, off by default behind "Save annotation data next to screenshots". The format is the contract the later work needs, and writing it for every capture would clutter the folder for users who never use it.

**5. Seams.** Four types, none touching `AppDelegate`, `BoardManager.shared`, or `OverlayView`:

- `DisplayCapturing`: where pixels come from. `ScreenSampler` conforms; tests stub it.
- `Capture`: what a capture is. The composited `CGImage`, `DisplayInfo` (id, frame, scale), the region in display-local points, board state, the annotation records, `capturedAt` wall clock, and `hostTime`.
- `AnnotationRenderer`: draws a document value plus board state into a `CGContext` with options (fade policy, live previews off). Selection chrome stays in `OverlayView`, which paints it over the renderer's output, so the renderer never draws chrome.
- `CaptureSink`: where it goes. `FileSink` and `ClipboardSink` in v1, a bundle sink later. `CaptureService.capture(request) async throws` wires them; `AnnotateCommand.capture` starts it and returns `.ran`, and the intents await it to return an `IntentFile`.

Timestamps and ids: `creationTime` is `CACurrentMediaTime`, mach host time, and ScreenCaptureKit stamps frames with host-time `displayTime`, so one clock covers both. The sidecar names the clock and records `hostTime` at capture plus ISO 8601 wall time, so a reader can align or convert. Add `id = UUID()` to the other annotation structs following `TextAnnotation` (not part of `==`, fresh on paste) in the sidecar PR. Numbered pins are the Counter tool; export them as `pin` with number, position, and time. Export through a DTO with sRGB hex colors and display-local top-left points, never `Codable` on the live structs, which hold `NSColor` and cached paths.

**6. Edge cases.**

- Fading strokes: full-screen capture renders what is on screen (current alpha, fully faded excluded). The area picker freezes `fadeClock` while open and captures at the frozen time. Fade resumes on dismiss.
- Active text edit: commit it first, as `hideOverlays` does. The capture shortcut works while a label is being typed when its binding has Command, which no typed character carries: it commits the label and captures, the same as the menu item. Every other overlay shortcut, and a capture binding without Command, still types into the label.
- Redactions: in a file the pixels under a redaction are permanent and the fresh snapshot holds the raw screen, so the renderer always lays the opaque placeholder and then the sample, never at fade alpha. Pixelate and Blur samples come from the capture's own snapshot through `ScreenSampler.makeSample`, not the stored `Rectangle.sample`, which can be stale against the fresh pixels. The `RedactionTests` leak assertions run against renderer output.
- Success HUD: respects `hideToolFeedback` like every other pill; the system notification is the channel for users who hide pills.
- Picker keys: the picker consumes Escape before `OverlayWindow.keyDown`, which otherwise closes the overlay.
- Toolbar, HUD, picker, cursor effects: never in the image, because Annotate's windows are excluded and the renderer draws only the document. `showsCursor` stays false.
- Always-On: Capture Screen works from the menu, a link, or an intent; the overlay is read-only but visible, so annotations render. Capture Area opens the interactive overlay first, as in answer 3.
- Board: fill at its opacity over the screen pixels, no 1 pt border. Redactions render solid, matching the screen.
- Full-screen Spaces: display capture sees the full-screen app; the overlay's `.canJoinAllSpaces` means annotations are there too.
- macOS 15 and later show a periodic ScreenCaptureKit reminder alert; it will sit under an open overlay until it closes. Already true for Redact; capture widens exposure.

**7. Shortcuts and links.** Yes. `AnnotateCommand.capture(CaptureScope)` with `screen` and `area` gives `annotate://capture/screen` and `annotate://capture/area`, plus Capture Screen and Capture Area intents returning the PNG as an `IntentFile`. Overlay shortcuts `captureScreen` (⌘S) and `captureArea` (⇧⌘S), rebindable, through `newlyEditable`; `s` is free of reserved keys and fixed key equivalents. Status menu items for both. "Open an image to annotate" needs a parameter the link parser rejects by design; when it comes, it is an intent with a file parameter.

**8. Stacked PRs.**

1. Renderer extraction. `AnnotationRenderer` from `OverlayView`'s draw code, `OverlayView.draw` delegates, zero behavior change. Tests: existing offscreen pixel tests pass unchanged; new renderer tests for chrome-off, fade policy, and redaction opacity. Cost: moving baselined SwiftLint violations surfaces them. Conflicts with any parallel `OverlayView` work.
2. Capture Screen. `DisplayCapturing`, `Capture`, `CaptureService`, `FileSink`, `ClipboardSink` (the default saves and copies), PNG encode off main, HUD, Capture pane with default folder and the Screen Recording row moved from Tools, `ShortcutKey.captureScreen`, menu item, `AnnotateCommand.capture(.screen)`. Tests: composite pixels against a stub snapshot (board on and off, scale 1 and 2), file naming and collisions, clipboard contents, display selection rule, command outcome. Mac: Retina plus external display, board, fade, Always-On, denied permission flow.
3. Capture Area. `RegionPicker`, fade freeze, crop, `captureArea`, opening the interactive overlay when none is open. Tests: picker geometry and keys, rect normalization, crop math, frozen clock, opening from a hidden or Always-On overlay. Mac: drag on each display, Escape, tiny rects, picker on a display whose overlay is not key, Always-On.
4. Folder, destinations, notification. Entitlement change, bookmark key and stale handling, the after-capture destination setting, notification protocol and stub. Tests: bookmark round trip in a temp directory, stale fallback, destination setting. Mac: a notarized build, pick a folder on an external volume, revoke it, click the notification.
5. Intents and links, README, AGENTS. Tests in `AnnotateCommandTests`, `URLCommandTests`, intent display representations.
6. Sidecar and ids. `CaptureRecord` v1, ids on annotations, the toggle, a schema doc under `docs/`. Tests: golden JSON, coordinate transform, clock fields.

**9. Risks.** The renderer extraction is the regression risk; pixel tests and a no-behavior-change rule contain it. Permission UX: the prompt and the macOS 15 reminder both hide under the overlay, so every prompt comes from Settings. Entitlement changes touch notarization; PR 4 needs a signed build check. 5K composites peak around 200 MB; encode off main. CI has no Screen Recording, so nothing in tests may call ScreenCaptureKit, which the protocol enforces.

## Later work

Keep `AnnotationRenderer`, `DisplayCapturing`, `Capture`, `CaptureRecord`, and `RegionPicker` free of app singletons and view types, so any of them can move without a rewrite. The JSON schema is versioned in `docs/`.

For the session feature, v1 does differently because of it: a renderer that draws into any context, a region enum with room for windows, a `Capture` value with host time and display info, a sink protocol so a bundle is a new sink, and ids on every annotation. What v1 avoids: window-id coupling (overlays are recreated on display changes), rendering bound to `NSView`, and a JSON shape derived from the live structs.

## Approve

1. Composite path (ScreenCaptureKit minus Annotate, plus in-process render), not window capture.
2. One display per capture; annotations only when that overlay is visible.
3. Fade freeze during the area picker; full-screen capture is what you see, at each annotation's current fade.
4. Default folder `~/Pictures/Annotate` with the Pictures entitlement; custom folder by bookmark.
5. Save and copy to the clipboard by default; HUD plus system notification, authorization from Settings only.
6. Sidecar shipped off by default; ids on every annotation.
7. Names Capture Screen and Capture Area, ⌘S and ⇧⌘S, `annotate://capture/<screen|area>`.
8. A sixth Settings pane, Capture, which also takes the Screen Recording row from Tools.

## Decisions

Settled 2026-11-01 from the open questions.

- After a capture: save the file and also copy it to the clipboard. "Both" is the default destination.
- Capture Area with no interactive overlay open, including Always-On: open the interactive overlay and show the picker.
- Full-screen capture in Fade Mode: annotations at their current fade, as shown on screen.
- The Redact Screen Recording permission row moves from the Tools pane into the Capture pane.
- Capture settings get their own Settings pane, Capture.
