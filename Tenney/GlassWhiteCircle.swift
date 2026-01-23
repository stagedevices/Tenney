//
//  GlassWhiteCircle.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/20/26.
//

import Foundation
import SwiftUI
import UIKit

 
// MARK: - Glass styling helper

public struct GlassBlueCircle: ViewModifier {
   public func body(content: Content) -> some View {
        content
            // keep the glyph crisp above the glass plate
            .foregroundStyle(.primary)

            // ✅ glass belongs on a background “plate”, not on the glyph
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(.blue), in: Circle())
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }

            // ✅ specular / rim highlight (this is what makes it read “liquid”)
            .overlay {
                // top-left sheen
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.30), location: 0.00),
                                .init(color: .white.opacity(0.10), location: 0.22),
                                .init(color: .clear,              location: 0.70)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)

                // rim
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
                    .blendMode(.overlay)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}

// Neutral / white glass circle for export button
public struct GlassWhiteCircle: ViewModifier {
  public func body(content: Content) -> some View {
        content
            // keep the glyph crisp above the glass plate
            .foregroundStyle(.primary)

            // ✅ glass belongs on a background “plate”, not on the glyph
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(.white), in: Circle())
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }

            // ✅ specular / rim highlight (this is what makes it read “liquid”)
            .overlay {
                // top-left sheen
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.30), location: 0.00),
                                .init(color: .white.opacity(0.10), location: 0.22),
                                .init(color: .clear,              location: 0.70)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)

                // rim
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
                    .blendMode(.overlay)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}

struct GlassWhiteCircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    var size: CGFloat = 44
    var font: Font = .system(size: 16, weight: .semibold)

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .font(font)
                .frame(width: size, height: size)
                .modifier(GlassWhiteCircle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
public struct GlassRedRoundedRect: ViewModifier {
    
    let corner: CGFloat
    public func body(content: Content) -> some View {
        let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.red), in: rr)
        } else {
            content
                .background(.ultraThinMaterial, in: rr)
                .background(rr.fill(Color.red.opacity(0.28)))
                .overlay(rr.stroke(Color.red.opacity(0.45), lineWidth: 1))
        }
    }
}

// Neutral glass rounded rect (used for Preview + other non-destructive actions).
public struct GlassRoundedRect: ViewModifier {
    let corner: CGFloat

    public func body(content: Content) -> some View {
        let rr = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: rr)
                .overlay(rr.stroke(Color.secondary.opacity(0.16), lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: rr)
                .overlay(rr.stroke(Color.secondary.opacity(0.18), lineWidth: 1))
        }
    }
}

// Subtle press feedback for glass buttons (kept separate from borderedProminent states).
struct GlassPressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}
