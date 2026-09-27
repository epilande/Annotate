import Sparkle
import SwiftUI

struct AboutView: View {
    private let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Annotate"
    }


    var body: some View {
        VStack(spacing: 20) {
            // App Icon and Name
            VStack(spacing: 12) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text("A")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
                
                VStack(spacing: 4) {
                    Text(appName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .padding(.horizontal)
            
            // Update Section
            VStack(spacing: 12) {
                Button("Check for Updates") {
                    updaterController.checkForUpdates(nil)
                }
                .buttonStyle(.borderedProminent)
                
                Text("Automatic updates are enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal)
            
            // Links and Attribution
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Link("GitHub", destination: URL(string: "https://github.com/epilande/Annotate")!)
                        .font(.caption)
                    
                    Link("Report Issue", destination: URL(string: "https://github.com/epilande/Annotate/issues")!)
                        .font(.caption)
                }
                
                Text("Created by epilande")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

#Preview {
    AboutView(updaterController: SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    ))
}
