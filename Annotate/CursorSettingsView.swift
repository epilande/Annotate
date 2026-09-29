import Combine
import SwiftUI
import UniformTypeIdentifiers

struct CursorSettingsView: View {
    @State private var clickEffectsEnabled: Bool = CursorHighlightManager.shared.clickEffectsEnabled
    @State private var cursorHighlightEnabled: Bool = CursorHighlightManager.shared.cursorHighlightEnabled
    @State private var spotlightRequiresOverlay: Bool = CursorHighlightManager.shared.spotlightRequiresOverlay
    @State private var excludedAppBundleIDs: [String] = CursorHighlightManager.shared.excludedAppBundleIDs
    @State private var effectColor: Color = Color(CursorHighlightManager.shared.effectColor)
    @State private var effectSize: Double = Double(CursorHighlightManager.shared.effectSize)
    @State private var spotlightSize: Double = Double(CursorHighlightManager.shared.spotlightSize)
    @State private var spotlightDimmingEnabled: Bool = CursorHighlightManager.shared.spotlightDimmingEnabled
    @State private var spotlightAutoDimEnabled: Bool = CursorHighlightManager.shared.spotlightAutoDimEnabled
    @State private var spotlightDimmingOpacity: Double =
        Double(CursorHighlightManager.shared.spotlightDimmingOpacity) * 100
    @State private var activeCursorStyle: ActiveCursorStyle = CursorHighlightManager.shared.activeCursorStyle
    @State private var activeCursorSize: Double = Double(CursorHighlightManager.shared.activeCursorSize)

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .cursor)
            }

            Section {
                LabeledContent {
                    ActiveCursorPreview(
                        style: activeCursorStyle,
                        color: CursorHighlightManager.shared.annotationColor,
                        size: CGFloat(activeCursorSize)
                    )
                } label: {
                    Text("Cursor Style")
                    Text("Choose how the cursor appears while annotating")
                }

                Picker("Cursor Style", selection: $activeCursorStyle) {
                    ForEach(ActiveCursorStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: activeCursorStyle) { _, newValue in
                    CursorHighlightManager.shared.activeCursorStyle = newValue
                }

                if activeCursorStyle == .circle || activeCursorStyle == .crosshair {
                    SettingsSliderRow(
                        title: "Cursor Size",
                        value: $activeCursorSize,
                        range: 8...24,
                        boundsText: { "\(Int($0))" }
                    )
                    .onChange(of: activeCursorSize) { _, newValue in
                        Task { @MainActor in
                            CursorHighlightManager.shared.activeCursorSize = CGFloat(newValue)
                        }
                    }
                }
            } header: {
                SettingsHeader(
                    icon: "cursorarrow",
                    color: .purple,
                    title: "Active Cursor",
                    subtitle: "Cursor appearance when overlay is active"
                )
            }

            Section {
                Toggle(isOn: $cursorHighlightEnabled) {
                    Text("Enable Cursor Spotlight")
                    Text("Show spotlight following cursor")
                }
                .onChange(of: cursorHighlightEnabled) { _, _ in
                    CursorHighlightManager.shared.cursorHighlightEnabled = cursorHighlightEnabled
                }

                if cursorHighlightEnabled {
                    SettingsSliderRow(
                        title: "Spotlight Size",
                        value: $spotlightSize,
                        range: 30...100,
                        boundsText: { "\(Int($0))" }
                    )
                    .onChange(of: spotlightSize) { _, newValue in
                        Task { @MainActor in
                            CursorHighlightManager.shared.spotlightSize = CGFloat(newValue)
                        }
                    }

                    Toggle(isOn: $spotlightDimmingEnabled) {
                        Text("Dim Background")
                        Text("Darken the screen except around the cursor")
                    }
                    .onChange(of: spotlightDimmingEnabled) { _, _ in
                        CursorHighlightManager.shared.spotlightDimmingEnabled = spotlightDimmingEnabled
                    }

                    if spotlightDimmingEnabled {
                        SettingsSliderRow(
                            title: "Dimming Amount",
                            value: $spotlightDimmingOpacity,
                            range: 20...90,
                            boundsText: { "\(Int($0))%" }
                        )
                        .onChange(of: spotlightDimmingOpacity) { _, newValue in
                            Task { @MainActor in
                                CursorHighlightManager.shared.spotlightDimmingOpacity = CGFloat(newValue / 100)
                            }
                        }
                    }

                    Toggle(isOn: $spotlightAutoDimEnabled) {
                        Text("Dim Automatically")
                        Text("Turn on background dimming whenever the spotlight is enabled")
                    }
                    .onChange(of: spotlightAutoDimEnabled) { _, _ in
                        CursorHighlightManager.shared.spotlightAutoDimEnabled = spotlightAutoDimEnabled
                    }

                    Toggle(isOn: $spotlightRequiresOverlay) {
                        Text("Only Show While Annotating")
                        Text("Show the spotlight only while the overlay is active")
                    }
                    .onChange(of: spotlightRequiresOverlay) { _, _ in
                        CursorHighlightManager.shared.spotlightRequiresOverlay = spotlightRequiresOverlay
                    }
                }

                Toggle(isOn: $clickEffectsEnabled) {
                    Text("Enable Click Effect")
                    Text("Ripple on click + highlight while holding")
                }
                .onChange(of: clickEffectsEnabled) { _, _ in
                    CursorHighlightManager.shared.clickEffectsEnabled = clickEffectsEnabled
                }

                if clickEffectsEnabled {
                    SettingsSliderRow(
                        title: "Click Effect Size",
                        value: $effectSize,
                        range: 30...100,
                        boundsText: { "\(Int($0))" }
                    )
                    .onChange(of: effectSize) { _, newValue in
                        Task { @MainActor in
                            CursorHighlightManager.shared.effectSize = CGFloat(newValue)
                        }
                    }
                }

                if clickEffectsEnabled || cursorHighlightEnabled {
                    LabeledContent {
                        HStack(spacing: 6) {
                            ForEach(Array(colorPalette.enumerated()), id: \.offset) { _, color in
                                PresetColorButton(
                                    color: color,
                                    isSelected: NSColor(effectColor).isClose(to: color)
                                ) {
                                    effectColor = Color(color)
                                    CursorHighlightManager.shared.effectColor = color
                                }
                            }
                        }
                    } label: {
                        Text("Effect Color")
                    }
                }
            } header: {
                SettingsHeader(
                    icon: "cursorarrow.motionlines",
                    color: .pink,
                    title: "Cursor Highlight",
                    subtitle: "Spotlight and click effects for presentations"
                )
            }

            if clickEffectsEnabled || cursorHighlightEnabled {
                Section {
                    if excludedAppBundleIDs.isEmpty {
                        Text("No excluded applications")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(excludedAppBundleIDs, id: \.self) { bundleID in
                            ExcludedAppRow(
                                bundleID: bundleID,
                                onRemove: {
                                    removeExcludedApp(bundleID)
                                }
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: addApplication) {
                            Image(systemName: "plus")
                                .frame(width: 14, height: 14)
                        }
                        .help("Add application to exclusion list")
                        .accessibilityLabel("Add application to exclusion list")

                        Spacer()
                    }
                    .padding(.top, 2)
                } header: {
                    SettingsHeader(
                        icon: "cursorarrow.slash",
                        color: .blue,
                        title: "Hide Cursor Effects In",
                        subtitle: "Suppress effects while one of these apps is focused"
                    )
                } footer: {
                    Text("Useful for virtual machines (such as UTM), games, and remote desktop clients that capture or lock the cursor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .settingsScrollEdgeEffect()
        .onAppear {
            syncState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorHighlightStateChanged)) { _ in
            syncState()
        }
    }

    /// Pulls the current manager values into local state so external changes
    /// (menu bar toggles, shortcuts) are reflected while the pane is open.
    private func syncState() {
        clickEffectsEnabled = CursorHighlightManager.shared.clickEffectsEnabled
        cursorHighlightEnabled = CursorHighlightManager.shared.cursorHighlightEnabled
        spotlightRequiresOverlay = CursorHighlightManager.shared.spotlightRequiresOverlay
        excludedAppBundleIDs = CursorHighlightManager.shared.excludedAppBundleIDs
        effectColor = Color(CursorHighlightManager.shared.effectColor)
        effectSize = Double(CursorHighlightManager.shared.effectSize)
        spotlightSize = Double(CursorHighlightManager.shared.spotlightSize)
        spotlightDimmingEnabled = CursorHighlightManager.shared.spotlightDimmingEnabled
        spotlightAutoDimEnabled = CursorHighlightManager.shared.spotlightAutoDimEnabled
        spotlightDimmingOpacity = Double(CursorHighlightManager.shared.spotlightDimmingOpacity) * 100
        activeCursorStyle = CursorHighlightManager.shared.activeCursorStyle
        activeCursorSize = Double(CursorHighlightManager.shared.activeCursorSize)
    }

    /// Opens an `NSOpenPanel` restricted to application bundles (`.app`) so the user can select applications to exclude.
    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Exclude Application"
        panel.prompt = "Exclude"
        panel.message = "Choose an application to suppress cursor spotlight and click effects in."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        let handleURLs: ([URL]) -> Void = { urls in
            let bundleIDs = urls.compactMap { url -> String? in
                let resolvedURL = url.resolvingSymlinksInPath()
                return Bundle(url: resolvedURL)?.bundleIdentifier
                    ?? (NSDictionary(contentsOf: resolvedURL.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String)
            }
            CursorHighlightManager.shared.addExcludedApps(bundleIDs: bundleIDs)
            excludedAppBundleIDs = CursorHighlightManager.shared.excludedAppBundleIDs
        }

        if let window = SettingsWindowManager.shared.settingsWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK {
                    handleURLs(panel.urls)
                }
            }
        } else {
            if panel.runModal() == .OK {
                handleURLs(panel.urls)
            }
        }
    }

    private func removeExcludedApp(_ bundleID: String) {
        CursorHighlightManager.shared.removeExcludedApp(bundleID: bundleID)
        excludedAppBundleIDs = CursorHighlightManager.shared.excludedAppBundleIDs
    }
}

/// Row representing an excluded application in cursor settings, showing its icon, name, and bundle ID.
private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(appName)")
            .accessibilityLabel("Remove \(appName)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
    }

    /// Resolves the application icon, or returns a generic system placeholder icon if not installed.
    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: bundleID)
            ?? NSWorkspace.shared.icon(for: .application)
    }

    /// Resolves the localized display name for the application, falling back to the bundle identifier if not installed.
    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}

private struct PresetColorButton: View {
    let color: NSColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwiftUI.Circle()
                .fill(Color(color))
                .frame(width: 24, height: 24)
                .overlay(
                    SwiftUI.Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    SwiftUI.Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ActiveCursorPreview: View {
    let style: ActiveCursorStyle
    let color: NSColor
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            switch style {
            case .none:
                drawPointerCursor(context: context, center: center, outerColor: .white)

            case .outline:
                drawPointerCursor(context: context, center: center, outerColor: Color(color))

            case .circle:
                let innerSize = size * 0.4
                let strokeWidth = max(2.0, size / 10)
                let outerRect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                let innerRect = CGRect(x: center.x - innerSize / 2, y: center.y - innerSize / 2, width: innerSize, height: innerSize)

                context.stroke(Path(ellipseIn: outerRect), with: .color(Color(color)), lineWidth: strokeWidth)
                context.fill(Path(ellipseIn: innerRect), with: .color(Color(color)))

            case .crosshair:
                var path = Path()
                path.move(to: CGPoint(x: center.x - size / 2, y: center.y))
                path.addLine(to: CGPoint(x: center.x + size / 2, y: center.y))
                path.move(to: CGPoint(x: center.x, y: center.y - size / 2))
                path.addLine(to: CGPoint(x: center.x, y: center.y + size / 2))

                context.stroke(path, with: .color(Color(color)), lineWidth: max(2.5, size / 5))
            }
        }
        .frame(width: 40, height: 40)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func drawPointerCursor(context: GraphicsContext, center: CGPoint, outerColor: Color) {
        let offsetX = center.x - 5.7
        let offsetY = center.y - 9.25

        var outerPath = Path()
        outerPath.move(to: CGPoint(x: offsetX, y: offsetY))
        outerPath.addLine(to: CGPoint(x: offsetX, y: offsetY + 16))
        outerPath.addLine(to: CGPoint(x: offsetX + 3.3, y: offsetY + 13.2))
        outerPath.addLine(to: CGPoint(x: offsetX + 6.1, y: offsetY + 18.5))
        outerPath.addLine(to: CGPoint(x: offsetX + 8, y: offsetY + 17.5))
        outerPath.addLine(to: CGPoint(x: offsetX + 9.6, y: offsetY + 16.6))
        outerPath.addLine(to: CGPoint(x: offsetX + 7, y: offsetY + 11.8))
        outerPath.addLine(to: CGPoint(x: offsetX + 11.4, y: offsetY + 11.8))
        outerPath.closeSubpath()

        var innerPath = Path()
        innerPath.move(to: CGPoint(x: offsetX + 1, y: offsetY + 2.8))
        innerPath.addLine(to: CGPoint(x: offsetX + 1, y: offsetY + 14))
        innerPath.addLine(to: CGPoint(x: offsetX + 3.5, y: offsetY + 11.6))
        innerPath.addLine(to: CGPoint(x: offsetX + 6.3, y: offsetY + 16.8))
        innerPath.addLine(to: CGPoint(x: offsetX + 8.2, y: offsetY + 15.9))
        innerPath.addLine(to: CGPoint(x: offsetX + 5.4, y: offsetY + 10.7))
        innerPath.addLine(to: CGPoint(x: offsetX + 9, y: offsetY + 10.7))
        innerPath.closeSubpath()

        context.fill(outerPath, with: .color(outerColor))
        context.fill(innerPath, with: .color(.black))
    }
}
