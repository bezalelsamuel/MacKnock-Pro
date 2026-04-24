// MenuBarView.swift
// MacKnock Pro
//
// Menu bar popover with status, quick controls, and last knock info.

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
                .padding(.horizontal)
            
            // Status Card
            statusCard

            if !appState.hasRootPrivileges {
                rootRequiredNotice
            }
            
            // Last Knock Info
            if let knockTime = appState.lastKnockTime {
                lastKnockCard(time: knockTime)
            }
            
            Divider()
                .padding(.horizontal)
            
            // Quick Controls
            quickControls
            
            Divider()
                .padding(.horizontal)
            
            // Bottom Actions
            bottomActions
        }
        .padding(.vertical, 12)
        .frame(width: 320)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "6C5CE7"), Color(hex: "A29BFE")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MacKnock Pro")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                
                Text(appState.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Power toggle
            Toggle("", isOn: Binding(
                get: { settings.isEnabled },
                set: { appState.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Color(hex: "6C5CE7"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack(spacing: 16) {
            statBubble(
                icon: "hand.tap",
                value: "\(appState.totalKnocks)",
                label: "Knocks"
            )
            
            statBubble(
                icon: "waveform.path.ecg",
                value: String(format: "%.0f Hz", appState.accelerometer.samplesPerSecond),
                label: "Sample Rate"
            )
            
            statBubble(
                icon: "gauge.medium",
                value: profileName,
                label: "Profile"
            )
        }
        .padding(12)
    }
    
    private var profileName: String {
        KnockProfile.profile(for: settings.activeProfile)?.name ?? "Custom"
    }
    
    private func statBubble(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "6C5CE7"))
            
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }
    
    // MARK: - Last Knock Card

    private var rootRequiredNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "E17055"))

            Text("Sensor access requires sudo. Launch the app from Terminal with root privileges.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func lastKnockCard(time: Date) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "00B894").opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "00B894"))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Last Knock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    Text(time, style: .relative)
                        .font(.system(size: 12, weight: .semibold))
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.4fg", appState.lastKnockAmplitude))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "6C5CE7"))
                }
            }
            
            Spacer()
            
            // Amplitude indicator
            amplitudeIndicator(appState.lastKnockAmplitude)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func amplitudeIndicator(_ amplitude: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(index: i, amplitude: amplitude))
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }
    }
    
    private func barColor(index: Int, amplitude: Double) -> Color {
        let threshold = Double(index) * 0.1
        if amplitude > threshold {
            return index < 3 ? Color(hex: "00B894") : Color(hex: "FDCB6E")
        }
        return Color.secondary.opacity(0.2)
    }
    
    // MARK: - Quick Controls
    
    private var quickControls: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Sensitivity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "%.2f", settings.minAmplitude))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "6C5CE7"))
            }
            
            Slider(
                value: $settings.minAmplitude,
                in: 0.01...0.50,
                step: 0.01
            )
            .tint(Color(hex: "6C5CE7"))
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Bottom Actions
    
    private var bottomActions: some View {
        VStack(spacing: 2) {
            Button(action: {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }) {
                Label("Settings...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuItemButtonStyle())
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit MacKnock Pro", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuItemButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

// MARK: - Menu Item Button Style

struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
