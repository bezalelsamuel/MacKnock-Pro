// MainSettingsView.swift
// MacKnock Pro
//
// Full settings window with tabbed interface.

import SwiftUI
import AppKit

struct MainSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsManager
    
    @State private var selectedTab: SettingsTab = .general
    @State private var didCopyLaunchCommand = false
    
    var body: some View {
        HSplitView {
            // Sidebar
            sidebar
                .frame(width: 200)
            
            // Content
            ScrollView {
                contentForTab(selectedTab)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(spacing: 2) {
            // App Header
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6C5CE7"), Color(hex: "A29BFE")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color(hex: "6C5CE7").opacity(0.3), radius: 8, y: 4)
                    
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("MacKnock Pro")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                
                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.isListening ? Color(hex: "00B894") : Color.secondary)
                        .frame(width: 6, height: 6)
                    
                    Text(appState.isListening ? "Listening" : "Paused")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 20)
            
            Divider()
                .padding(.horizontal, 16)
            
            // Navigation items
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            Spacer()
            
            // Version
            Text("v1.0.0")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.5)
        )
    }
    
    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedTab == tab ? Color(hex: "6C5CE7") : .secondary)
                    .frame(width: 20)
                
                Text(tab.title)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Makes the entire row clickable including the spacer
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedTab == tab ? Color(hex: "6C5CE7").opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Content Router
    
    @ViewBuilder
    private func contentForTab(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            generalTab
        case .actions:
            ActionConfigView(actionExecutor: appState.actionExecutor)
                .environmentObject(appState)
                .environmentObject(settings)
        case .sensitivity:
            sensitivityTab
        case .monitor:
            monitorTab
        case .about:
            aboutTab
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("General", icon: "gear", subtitle: "Basic application settings")
            
            settingsCard {
                VStack(spacing: 16) {
                    toggleRow(
                        icon: "power",
                        title: "Enable Knock Detection",
                        subtitle: "Start listening for knocks when app launches",
                        isOn: Binding(
                            get: { settings.isEnabled },
                            set: { appState.setEnabled($0) }
                        )
                    )
                    
                    Divider()
                    
                    toggleRow(
                        icon: "sunrise",
                        title: "Launch at Login",
                        subtitle: "Automatically start MacKnock Pro when you log in",
                        isOn: $settings.launchAtLogin
                    )
                    
                    Divider()
                    
                    toggleRow(
                        icon: "speaker.wave.2",
                        title: "Sound Feedback",
                        subtitle: "Play a subtle sound when a knock is detected",
                        isOn: $settings.soundFeedback
                    )
                    
                    Divider()
                    
                    toggleRow(
                        icon: "bell",
                        title: "Show Notifications",
                        subtitle: "Display a notification banner for each knock",
                        isOn: $settings.showNotification
                    )
                }
            }
            
            sectionHeader("Appearance", icon: "paintbrush", subtitle: "Customize the menu bar icon")
            
            settingsCard {
                HStack(spacing: 12) {
                    Text("Menu Bar Icon")
                        .font(.system(size: 13, weight: .medium))
                    
                    Spacer()
                    
                    Picker("", selection: $settings.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                            Label(style.rawValue, systemImage: style.systemImage)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            
            // Sensor Status
            sectionHeader("Sensor Status", icon: "cpu", subtitle: "Accelerometer hardware information")
            
            settingsCard {
                VStack(spacing: 10) {
                    statusRow("Sensor Available", value: appState.sensorAvailable ? "Yes" : "No",
                             color: appState.sensorAvailable ? Color(hex: "00B894") : Color(hex: "FF6B6B"))
                    
                    Divider()
                    
                    statusRow("Sample Rate", value: String(format: "%.0f Hz", appState.accelerometer.samplesPerSecond))
                    
                    Divider()
                    
                    statusRow("Status", value: appState.isListening ? "Running" : "Stopped",
                             color: appState.isListening ? Color(hex: "00B894") : .secondary)
                }
            }

            sectionHeader("Root Access", icon: "lock.shield", subtitle: "Required for accelerometer HID access")

            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(
                        "Privilege Level",
                        value: appState.hasRootPrivileges ? "Root (sudo)" : "Standard user",
                        color: appState.hasRootPrivileges ? Color(hex: "00B894") : Color(hex: "E17055")
                    )

                    if !appState.hasRootPrivileges {
                        Divider()

                        Text("Launch command")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Text(appState.launchCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )

                        HStack {
                            Text("Without sudo, the app UI loads but sensor listening cannot start.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(didCopyLaunchCommand ? "Copied" : "Copy Command") {
                                copyLaunchCommand()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Sensitivity Tab
    
    private var sensitivityTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Sensitivity Profile", icon: "slider.horizontal.3", subtitle: "Choose a preset or customize detection sensitivity")

            // Profile Cards
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(KnockProfile.allProfiles, id: \.id) { profile in
                    profileCard(profile)
                }
            }

            // Adaptive ML Status Card
            sectionHeader("Adaptive Threshold Engine", icon: "brain",
                         subtitle: "Online learning — calibrates to your personal knock strength")

            adaptiveMLCard

            sectionHeader("Fine Tuning", icon: "tuningfork", subtitle: "Manual parameters (act as guards for the adaptive engine)")

            settingsCard {
                VStack(spacing: 16) {
                    // Amplitude Floor
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Noise Guard Floor")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Adaptive threshold cannot drop below this — blocks very soft ambient vibrations")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(String(format: "%.3f g", settings.minAmplitude))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "6C5CE7"))
                        }

                        Slider(value: $settings.minAmplitude, in: 0.005...0.30, step: 0.005)
                            .tint(Color(hex: "6C5CE7"))

                        HStack {
                            Text("Allow Soft Taps")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Hard Knocks Only")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Cooldown
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Cooldown Period")
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            Text("\(settings.cooldownMs) ms")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "6C5CE7"))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settings.cooldownMs) },
                                set: { settings.cooldownMs = Int($0) }
                            ),
                            in: 200...2000,
                            step: 50
                        )
                        .tint(Color(hex: "6C5CE7"))

                        HStack {
                            Text("Fast Response")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Slow Response")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Adaptive ML Card

    @ViewBuilder
    private var adaptiveMLCard: some View {
        let engine = appState.adaptiveEngine
        settingsCard {
            VStack(spacing: 14) {
                // Status header row
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(engine.isCalibratedEnough
                                  ? Color(hex: "00B894").opacity(0.15)
                                  : Color(hex: "FDCB6E").opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: engine.isCalibratedEnough ? "checkmark.seal.fill" : "brain")
                            .font(.system(size: 15))
                            .foregroundColor(engine.isCalibratedEnough
                                            ? Color(hex: "00B894")
                                            : Color(hex: "FDCB6E"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.isCalibratedEnough ? "Calibrated" : "Learning…")
                            .font(.system(size: 13, weight: .semibold))

                        Text(engine.statusDescription)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Separation confidence bar
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(format: "%.0f%%", engine.confidence * 100))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "6C5CE7"))

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "6C5CE7"), Color(hex: "00B894")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * engine.confidence)
                            }
                        }
                        .frame(width: 80, height: 6)

                        Text("Confidence")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Three-column stats
                HStack(spacing: 0) {
                    adaptiveStat(
                        label: "Noise Floor",
                        value: String(format: "%.4f g", engine.noiseMean),
                        color: Color(hex: "74B9FF")
                    )

                    Divider().frame(height: 36)

                    adaptiveStat(
                        label: "Adaptive Threshold",
                        value: String(format: "%.4f g", engine.threshold),
                        color: Color(hex: "6C5CE7")
                    )

                    Divider().frame(height: 36)

                    adaptiveStat(
                        label: "Your Knock Mean",
                        value: String(format: "%.4f g", engine.knockMean),
                        color: Color(hex: "00B894")
                    )
                }

                Divider()

                // Reset button
                HStack {
                    Text("Reset resets the learned model. The engine will re-learn after \(5) more knocks.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Reset Model") {
                        appState.detector.resetAdaptiveModel()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "FF6B6B"))
                }
            }
        }
    }

    private func adaptiveStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func profileCard(_ profile: KnockProfile) -> some View {
        let isActive = settings.activeProfile == profile.id
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.applyProfile(profile)
            }
        }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color(hex: "6C5CE7").opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: profile.icon)
                        .font(.system(size: 18))
                        .foregroundColor(isActive ? Color(hex: "6C5CE7") : .secondary)
                }
                
                Text(profile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isActive ? Color(hex: "6C5CE7") : .primary)
                
                Text(profile.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Values
                HStack(spacing: 8) {
                    miniStat("Amp", String(format: "%.2f", profile.minAmplitude))
                    miniStat("CD", "\(profile.cooldownMs)ms")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? Color(hex: "6C5CE7").opacity(0.5) : Color.secondary.opacity(0.1), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Monitor Tab
    
    private var monitorTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Live Monitor", icon: "waveform.path.ecg", subtitle: "Real-time accelerometer data visualization")
            
            // Waveform
            WaveformView()
                .environmentObject(appState)
                .frame(height: 200)
            
            // Start/Stop button
            HStack {
                Button(action: {
                    appState.toggleListening()
                }) {
                    Label(
                        appState.isListening ? "Stop Monitoring" : "Start Monitoring",
                        systemImage: appState.isListening ? "stop.fill" : "play.fill"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appState.isListening ? Color(hex: "FF6B6B") : Color(hex: "00B894"))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if appState.sensorAvailable {
                    Label("Sensor Available", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "00B894"))
                } else {
                    Label("Sensor Not Found", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "FF6B6B"))
                }
            }
            
            // Detection Events
            sectionHeader("Recent Events", icon: "list.bullet", subtitle: "Last detected vibration events")
            
            settingsCard {
                if appState.detector.events.isEmpty {
                    Text("No events detected yet. Start monitoring and tap your MacBook.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(appState.detector.events.suffix(20).reversed()) { event in
                                HStack(spacing: 8) {
                                    Text(event.severity.symbol)
                                        .frame(width: 16)
                                    
                                    Text(event.severity.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(event.isKnock ? .primary : .secondary)
                                    
                                    Spacer()
                                    
                                    Text(String(format: "%.5fg", event.amplitude))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Text(event.time, style: .time)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }
    
    // MARK: - About Tab
    
    private var aboutTab: some View {
        VStack(spacing: 24) {
            // App Icon & Name
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6C5CE7"), Color(hex: "A29BFE")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: Color(hex: "6C5CE7").opacity(0.4), radius: 12, y: 6)
                    
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("MacKnock Pro")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("Version 1.0.0")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            // Description
            Text("Detect physical knocks on your MacBook and trigger actions.\nUses the Apple Silicon MEMS accelerometer (Bosch BMI286 IMU)\nvia IOKit HID for real-time vibration detection.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Credits
            VStack(spacing: 12) {
                Text("Credits")
                    .font(.system(size: 14, weight: .semibold))
                
                VStack(spacing: 6) {
                    creditRow("Sensor reading & detection algorithms",
                             link: "olvvier/apple-silicon-accelerometer",
                             url: "https://github.com/olvvier/apple-silicon-accelerometer")
                    
                    creditRow("Vibration detection & Go port",
                             link: "taigrr/spank",
                             url: "https://github.com/taigrr/spank")
                }
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // System Info
            VStack(spacing: 8) {
                Text("System Information")
                    .font(.system(size: 14, weight: .semibold))
                
                let deviceInfo = appState.accelerometer.deviceInfo()
                let sensors = (deviceInfo["sensors"] as? [String]) ?? []
                
                HStack(spacing: 20) {
                    infoChip("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    infoChip("Sensors: \(sensors.joined(separator: ", "))")
                }
            }
            
            Spacer()
            
            Text("Made with ❤️ for M3 MacBook Air")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func creditRow(_ description: String, link: String, url: String) -> some View {
        VStack(spacing: 2) {
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Link(link, destination: URL(string: url)!)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "6C5CE7"))
        }
    }
    
    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
    
    // MARK: - Shared Components
    
    private func sectionHeader(_ title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "6C5CE7"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            )
    }
    
    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "6C5CE7"))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color(hex: "6C5CE7"))
    }
    
    private func statusRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
        }
    }

    private func copyLaunchCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.launchCommand, forType: .string)
        didCopyLaunchCommand = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyLaunchCommand = false
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case actions = "Actions"
    case sensitivity = "Sensitivity"
    case monitor = "Monitor"
    case about = "About"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .general:     return "gear"
        case .actions:     return "hand.tap.fill"
        case .sensitivity: return "slider.horizontal.3"
        case .monitor:     return "waveform.path.ecg"
        case .about:       return "info.circle"
        }
    }
}
