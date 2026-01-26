//
//  AcknowledgementsView.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/17/26.
//

//
//  AcknowledgementsView.swift
//  Tenney
//

import Foundation
import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.tenneyTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let githubURL = URL(string: "https://github.com/stagedevices/Tenney")!
    private let zipFoundationURL = URL(string: "https://github.com/weichsel/ZIPFoundation")!
    private let sentryURL = URL(string: "https://sentry.io")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                creditsCard
                technologyCard
                legalCard
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acknowledgements")
                .font(.title3.weight(.bold))

            Text("Tenney is made possible by open-source tools and the work of the wider tuning community.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .modifier(MuseumCard(corner: 18, theme: theme, emphasize: true))
    }
    private var creditsCard: some View {
        AckCard("Credits", systemImage: "sparkles") {
            AckRow(
                title: "James Tenney estate",
                detail: "Tenney is named in honor of composer James Tenney. Thanks to the James Tenney estate for stewardship of his legacy.",
                systemImage: "music.quarternote.3",
                url: nil
            )

            AckRow(
                title: "Joe Monzo",
                detail: "Monzo vector notation (prime-exponent representation) is used in Tenney’s tuning/lattice plumbing. Thanks to Joe Monzo for his foundational writing and pedagogy around this notation.",
                systemImage: "function",
                url: nil
            )

            AckRow(
                title: "CalArts community & beta testers",
                detail: "Thanks to the CalArts community and early beta testers for feedback, bug reports, and careful ears.",
                systemImage: "person.2",
                url: nil
            )

            AckRow(
                title: "Open-source contributors",
                detail: "And to everyone shipping patches, issues, and docs — thank you.",
                systemImage: "hammer",
                url: githubURL
            )
        }
    }

    private var technologyCard: some View {
        AckCard("Technology", systemImage: "cpu") {
            AckRow(
                title: "Sentry",
                detail: "Crash reporting & diagnostics",
                systemImage: "stethoscope",
                url: sentryURL
            )

            AckRow(
                title: "ZIPFoundation",
                detail: "ZIP archive support",
                systemImage: "shippingbox",
                url: zipFoundationURL
            )
        }
    }

    private var legalCard: some View {
        AckCard("Legal", systemImage: "checkmark.seal") {
            NavigationLink {
                LicensesView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())

                    Text("Open-source licenses")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }


}


private struct AckRow: View {
    let title: String
    let detail: String?
    let systemImage: String
    let url: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28, height: 28)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

private struct AckCard<Content: View>: View {
    @Environment(\.tenneyTheme) private var theme
    let title: String
    let systemImage: String
    let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(16)
        .modifier(MuseumCard(corner: 16, theme: theme))
    }
}

private struct LicensesView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    LicenseDetailView(
                        title: "ZIPFoundation (MIT License)",
                        licenseText: LicenseDetailView.mitLicenseText
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZIPFoundation")
                            .font(.subheadline.weight(.semibold))
                        Text("MIT License")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
            } header: {
                Text("PACKAGES")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseDetailView: View {
    let title: String
    let licenseText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(licenseText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("License")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let mitLicenseText: String =
    """
    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
    """
}
