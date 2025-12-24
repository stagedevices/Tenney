
//
//  AboutView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/19/25.
//

import Foundation
import SwiftUI
import StoreKit
import UIKit

enum AboutAppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Tenney"
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    private var websiteURL: URL? { URL(string: "https://www.stagedevices.com") }
    private var supportURL: URL?  { URL(string: "https://www.stagedevices.com/support") }
    private var privacyURL: URL?  { URL(string: "https://www.stagedevices.com/privacy") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                header

                VStack(spacing: 12) {
                    infoCard
                    linksCard
                    creditsCard
                    diagnosticsCard
                }
            }
            .padding(16)
        }
        .background(
            (scheme == .dark ? Color.black : Color.white)
                .opacity(0.001)
                .ignoresSafeArea()
        )
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                Image(systemName: "tuningfork")
                    .font(.system(size: 28, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 64, height: 64)
            .modifier(AboutGlass(corner: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(AboutAppInfo.name)
                    .font(.title3.weight(.bold))
                Text("v\(AboutAppInfo.version) (build \(AboutAppInfo.build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .modifier(AboutGlass(corner: 18))
    }

    // MARK: - Cards

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Version", systemImage: "number")
                .font(.headline)

            HStack {
                Text("App")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(AboutAppInfo.version)")
                    .font(.callout.weight(.semibold))
            }

            HStack {
                Text("Build")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(AboutAppInfo.build)")
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(14)
        .modifier(AboutGlass(corner: 16))
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Links", systemImage: "link")
                .font(.headline)

            HStack(spacing: 10) {
                if let websiteURL {
                    Link(destination: websiteURL) {
                        Label("Website", systemImage: "globe")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .glassControlRounded(12)
                }

                if let supportURL {
                    Link(destination: supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .glassControlRounded(12)
                }

                if let privacyURL {
                    Link(destination: privacyURL) {
                        Label("Privacy", systemImage: "hand.raised")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .glassControlRounded(12)
                }

                Spacer(minLength: 0)
            }

            Button {
                requestRating()
            } label: {
                Label("Rate Tenney", systemImage: "star.bubble")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .glassControlRounded(9999)
        }
        .padding(14)
        .modifier(AboutGlass(corner: 16))
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Credits", systemImage: "person.2.fill")
                .font(.headline)

            Text("Tenney is built around just-intonation lattice workflows: fast selection, clear labeling, and stage-ready presentation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("© Stage Devices LLC")
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .modifier(AboutGlass(corner: 16))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                .font(.headline)

            Button {
                UIPasteboard.general.string = "Tenney v\(AboutAppInfo.version) (\(AboutAppInfo.build))"
            } label: {
                Label("Copy version string", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .glassControlRounded(12)
        }
        .padding(14)
        .modifier(AboutGlass(corner: 16))
    }

    // MARK: - Rating

    private func requestRating() {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

// MARK: - Glass helpers

private struct AboutGlass: ViewModifier {
    let corner: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

fileprivate extension View {
    @ViewBuilder
    func glassControlRounded(_ corner: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}
