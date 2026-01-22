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
    @Environment(\.accessibilityIncreaseContrast) private var increaseContrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                packages
                licenses
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
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    ThemeAccent.shapeStyle(
                        base: theme.accent.opacity(0.55),
                        reduceTransparency: reduceTransparency,
                        increaseContrast: increaseContrast
                    ),
                    lineWidth: 1
                )
        )
    }

    private var packages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Packages", systemImage: "shippingbox")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 8) {
                bullet("ZipFoundation (SPM)")
                bullet("Tenney estate — acknowledgement")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var licenses: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Licenses", systemImage: "doc.text")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)

            LicenseBlock(title: "ZipFoundation (MIT License)", text: mitLicenseText)

            LicenseBlock(
                title: "Tenney estate",
                text: "Acknowledgement: Tenney draws inspiration from the work and legacy of James Tenney."
            )
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(s)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var mitLicenseText: String {
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
}

private struct LicenseBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
    }
}
