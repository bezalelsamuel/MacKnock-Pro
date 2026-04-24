// ActionConfigView.swift
// MacKnock Pro
//
// Configuration UI for mapping knock patterns to actions.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ActionConfigView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject var actionExecutor: ActionExecutor
    
    init(actionExecutor: ActionExecutor) {
        self.actionExecutor = actionExecutor
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 6) {
                Text("Knock Actions")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Text("Assign actions to double, triple, and quad knock patterns")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            
            // Pattern Cards
            VStack(spacing: 12) {
                ForEach(KnockPatternType.allCases) { pattern in
                    patternCard(for: pattern)
                }
            }
            .padding(.horizontal)
            
            // Recent Actions Log
            if !actionExecutor.recentActions.isEmpty {
                recentActionsSection
            }
            
            Spacer()
        }
    }
    
    // MARK: - Pattern Card
    
    private func patternCard(for pattern: KnockPatternType) -> some View {
        let binding = Binding<ActionConfiguration>(
            get: {
                actionExecutor.patternActions[pattern] ?? ActionConfiguration()
            },
            set: { newValue in
                actionExecutor.patternActions[pattern] = newValue
                actionExecutor.saveConfiguration()
            }
        )
        let validationMessage = actionExecutor.validationMessage(for: binding.wrappedValue)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // Pattern icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(patternGradient(pattern))
                        .frame(width: 44, height: 44)

                    Image(systemName: pattern.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Pattern info
                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.rawValue)
                        .font(.system(size: 14, weight: .semibold))

                    Text(pattern.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action picker
                Menu {
                    ForEach(ActionCategory.allCases, id: \.self) { category in
                        if category != .none {
                            Section(category.rawValue) {
                                ForEach(KnockActionType.allCases.filter { $0.category == category }) { action in
                                    Button(action: {
                                        var config = binding.wrappedValue
                                        config.actionType = action
                                        if !action.requiresParameter {
                                            config.parameter = ""
                                        }
                                        binding.wrappedValue = config
                                    }) {
                                        Label(action.rawValue, systemImage: action.icon)
                                    }
                                }
                            }
                        } else {
                            Button(action: {
                                var config = binding.wrappedValue
                                config.actionType = .none
                                config.parameter = ""
                                binding.wrappedValue = config
                            }) {
                                Label("None", systemImage: "nosign")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: binding.wrappedValue.actionType.icon)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "6C5CE7"))

                        Text(binding.wrappedValue.actionType.rawValue)
                            .font(.system(size: 12, weight: .medium))

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if binding.wrappedValue.actionType.requiresParameter {
                parameterEditor(for: binding)
            }

            if let validationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "FF6B6B"))

                    Text(validationMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "FF6B6B"))

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func parameterEditor(for binding: Binding<ActionConfiguration>) -> some View {
        let actionType = binding.wrappedValue.actionType

        VStack(alignment: .leading, spacing: 6) {
            Text(parameterLabel(for: actionType))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if actionType == .customScript {
                TextEditor(text: Binding(
                    get: { binding.wrappedValue.parameter },
                    set: { newValue in
                        var config = binding.wrappedValue
                        config.parameter = newValue
                        binding.wrappedValue = config
                    }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 84)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            } else {
                HStack(spacing: 8) {
                    TextField(
                        parameterPlaceholder(for: actionType),
                        text: Binding(
                            get: { binding.wrappedValue.parameter },
                            set: { newValue in
                                var config = binding.wrappedValue
                                config.parameter = newValue
                                binding.wrappedValue = config
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    
                    if actionType == .launchApp {
                        Button {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            
                            if panel.runModal() == .OK, let url = panel.url {
                                var config = binding.wrappedValue
                                config.parameter = url.path
                                binding.wrappedValue = config
                            }
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func parameterLabel(for action: KnockActionType) -> String {
        switch action {
        case .launchApp:
            return "App path or bundle identifier"
        case .runShortcut:
            return "Shortcut name"
        case .customScript:
            return "Shell script or AppleScript"
        default:
            return "Parameter"
        }
    }

    private func parameterPlaceholder(for action: KnockActionType) -> String {
        switch action {
        case .launchApp:
            return "/Applications/Music.app or com.apple.Music"
        case .runShortcut:
            return "Shortcut name"
        case .customScript:
            return ""
        default:
            return ""
        }
    }
    
    private func patternGradient(_ pattern: KnockPatternType) -> LinearGradient {
        switch pattern {
        case .double:
            return LinearGradient(
                colors: [Color(hex: "00B894"), Color(hex: "00CEC9")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .triple:
            return LinearGradient(
                colors: [Color(hex: "6C5CE7"), Color(hex: "A29BFE")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .quad:
            return LinearGradient(
                colors: [Color(hex: "E17055"), Color(hex: "FDCB6E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Recent Actions
    
    private var recentActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Actions")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Button("Clear") {
                    appState.actionExecutor.recentActions.removeAll()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.actionExecutor.recentActions.prefix(10)) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(entry.success ? Color(hex: "00B894") : Color(hex: "FF6B6B"))
                            
                            Text(entry.pattern.rawValue)
                                .font(.system(size: 11, weight: .medium))
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            
                            Text(entry.action.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(entry.time, style: .relative)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}
