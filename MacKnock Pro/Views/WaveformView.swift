// WaveformView.swift
// MacKnock Pro
//
// Real-time accelerometer waveform visualization using Canvas.

import SwiftUI
import Combine

struct WaveformView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var waveformData: [Double] = []
    @State private var waveformMaxVal: Double = 0.1
    @State private var knockMarkers: [KnockMarker] = []
    @State private var isVisible = false
    @State private var currentMagnitude: Double = 0
    @State private var currentRMS: Double = 0
    
    private let maxPoints = 500
    private let updateInterval: TimeInterval = 1.0 / 30.0  // 30 FPS
    
    var body: some View {
        VStack(spacing: 0) {
            // Waveform Canvas
            GeometryReader { geometry in
                ZStack {
                    // Background grid
                    gridBackground(size: geometry.size)
                    
                    // Waveform line
                    waveformPath(size: geometry.size)
                    
                    // Knock markers
                    knockMarkersOverlay(size: geometry.size)
                    
                    // Y-axis labels
                    yAxisLabels(size: geometry.size)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            
            // Stats bar
            statsBar
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onReceive(Timer.publish(every: updateInterval, on: .main, in: .common).autoconnect()) { _ in
            if isVisible {
                updateWaveformData()
            }
        }
    }
    
    // MARK: - Grid Background
    
    private func gridBackground(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridColor = Color.secondary.opacity(0.08)
            
            // Horizontal lines
            let hLines = 5
            for i in 0...hLines {
                let y = canvasSize.height * CGFloat(i) / CGFloat(hLines)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }
            
            // Vertical lines
            let vLines = 10
            for i in 0...vLines {
                let x = canvasSize.width * CGFloat(i) / CGFloat(vLines)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }
            
            // Center line (zero magnitude reference)
            let centerY = canvasSize.height * 0.7
            var centerPath = Path()
            centerPath.move(to: CGPoint(x: 0, y: centerY))
            centerPath.addLine(to: CGPoint(x: canvasSize.width, y: centerY))
            context.stroke(centerPath, with: .color(Color(hex: "6C5CE7").opacity(0.2)), lineWidth: 1)
        }
    }
    
    // MARK: - Waveform Path
    
    private func waveformPath(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard waveformData.count > 1 else { return }
            let visibleData = Array(waveformData.suffix(maxPoints))
            let pointCount = visibleData.count
            guard pointCount > 1 else { return }

            let maxVal = waveformMaxVal
            let baseline = canvasSize.height * 0.7
            let scale = canvasSize.height * 0.6 / maxVal
            
            // Create the waveform path
            var path = Path()
            var fillPath = Path()
            
            let step = canvasSize.width / CGFloat(pointCount - 1)
            
            for (i, value) in visibleData.enumerated() {
                let x = CGFloat(i) * step
                let y = baseline - CGFloat(value) * scale
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: x, y: baseline))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            // Close fill path
            let lastX = CGFloat(visibleData.count - 1) * step
            fillPath.addLine(to: CGPoint(x: lastX, y: baseline))
            fillPath.closeSubpath()
            
            // Draw gradient fill
            let gradient = Gradient(colors: [
                Color(hex: "6C5CE7").opacity(0.3),
                Color(hex: "6C5CE7").opacity(0.02),
            ])
            context.fill(
                fillPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )
            
            // Draw waveform line
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "A29BFE"), Color(hex: "6C5CE7")]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: canvasSize.width, y: 0)
                ),
                lineWidth: 1.5
            )
        }
    }
    
    // MARK: - Knock Markers
    
    private func knockMarkersOverlay(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let pointCount = min(waveformData.count, maxPoints)
            guard pointCount > 1 else { return }
            let step = canvasSize.width / CGFloat(pointCount - 1)
            let maxVal = waveformMaxVal
            let baseline = canvasSize.height * 0.7
            let scale = canvasSize.height * 0.6 / maxVal
            
            for marker in knockMarkers {
                if marker.position >= 0 && marker.position < pointCount {
                    let x = CGFloat(marker.position) * step
                    let y = baseline - CGFloat(marker.amplitude) * scale
                    
                    // Draw marker dot
                    let dotSize: CGFloat = 8
                    let dotRect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    
                    // Glow
                    let glowRect = dotRect.insetBy(dx: -3, dy: -3)
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(markerColor(marker.severity).opacity(0.3))
                    )
                    
                    // Dot
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(markerColor(marker.severity))
                    )
                    
                    // Vertical line
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: x, y: 0))
                    linePath.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(
                        linePath,
                        with: .color(markerColor(marker.severity).opacity(0.2)),
                        lineWidth: 1
                    )
                }
            }
        }
    }
    
    private func markerColor(_ severity: KnockSeverity) -> Color {
        switch severity {
        case .major: return Color(hex: "FF6B6B")
        case .shock: return Color(hex: "FDCB6E")
        case .micro: return Color(hex: "00B894")
        default: return Color.secondary
        }
    }
    
    // MARK: - Y-Axis Labels
    
    private func yAxisLabels(size: CGSize) -> some View {
        VStack {
            Text("0.5g")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 4)
            
            Spacer()
            
            Text("0g")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, size.height * 0.3)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 4)
    }
    
    // MARK: - Stats Bar
    
    private var statsBar: some View {
        HStack(spacing: 16) {
            Label {
                Text(String(format: "%.4fg", currentMagnitude))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            } icon: {
                Image(systemName: "waveform")
                    .foregroundColor(Color(hex: "6C5CE7"))
            }
            
            Label {
                Text(String(format: "%.4f", currentRMS))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            } icon: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(Color(hex: "00B894"))
            }
            
            Spacer()
            
            Text("\(waveformData.count) pts")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    
    // MARK: - Data Update
    
    private func updateWaveformData() {
        let data = appState.detector.waveform.slice()
        waveformData = data
        waveformMaxVal = max(data.max() ?? 0.1, 0.1)
        currentMagnitude = appState.detector.currentMagnitude
        currentRMS = appState.detector.currentRMS
        
        // Update knock markers
        let events = appState.detector.events.filter { $0.isKnock }
        let visibleCount = min(data.count, maxPoints)
        guard visibleCount > 0 else {
            knockMarkers = []
            return
        }

        let sampleRate = Double(appState.detector.sampleRate)
        let visibleDuration = Double(max(visibleCount - 1, 0)) / max(sampleRate, 1)
        let endTime = ProcessInfo.processInfo.systemUptime
        let startTime = endTime - visibleDuration
        let maxIndex = max(visibleCount - 1, 0)

        knockMarkers = events.suffix(10).compactMap { event in
            if maxIndex == 0 {
                return KnockMarker(
                    position: 0,
                    amplitude: event.amplitude,
                    severity: event.severity
                )
            }

            guard event.machTimestamp >= startTime, event.machTimestamp <= endTime else {
                return nil
            }

            let normalized = (event.machTimestamp - startTime) / max(visibleDuration, 1e-6)
            let pos = max(0, min(maxIndex, Int((normalized * Double(maxIndex)).rounded())))

            return KnockMarker(
                position: pos,
                amplitude: event.amplitude,
                severity: event.severity
            )
        }
    }
}

// MARK: - Knock Marker

struct KnockMarker {
    let position: Int
    let amplitude: Double
    let severity: KnockSeverity
}
