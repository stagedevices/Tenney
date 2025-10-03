//
//  DevOverlay.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//
import SwiftUI
import Combine
import QuartzCore

private struct OverlayGlassHUD: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(TenneyTokens.Color.glassBorder, lineWidth: 1)
                }
        }
    }
}


final class FPSCounter: ObservableObject {
    @Published var fps: Int = 0
    private var last = CACurrentMediaTime()
    private var frames = 0

    func tick() {
        frames += 1
        let now = CACurrentMediaTime()
        if now - last >= 1 {
            fps = frames
            frames = 0
            last = now
        }
    }
}

struct DevOverlay: ViewModifier {
    @StateObject private var counter = FPSCounter()
    @State private var thermal = ProcessInfo.processInfo.thermalState

    @Environment(\.accessibilityReduceTransparency) private var reduceTrans: Bool
    @Environment(\.colorSchemeContrast) private var contrast: ColorSchemeContrast

    @State private var ticker: Publishers.Autoconnect<Timer.TimerPublisher> =
        Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .onReceive(ticker) { _ in
                counter.tick()
                thermal = ProcessInfo.processInfo.thermalState
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Text("FPS \(counter.fps)")
                    Text("Therm \(thermal.rawValue)")
                    Text("RT \(reduceTrans ? "on" : "off")")
                    Text("Ctr \(contrast == .increased ? "↑" : "—")")
                }
                .font(.footnote)
                .padding(8)
                .modifier(GlassToolbarBackground())     // Apple glass background on bars/sheets
                .padding(10)
                .allowsHitTesting(false)
            }

    }
}

extension View {
    #if DEBUG
    func devOverlay() -> some View { modifier(DevOverlay()) }
    #else
    func devOverlay() -> some View { self }
    #endif
}
