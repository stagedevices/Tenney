#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

struct CatalystInspectorView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var latticeStore: LatticeStore
    let destination: CatalystDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch destination {
            case .lattice:
                latticeInspector
            case .tuner:
                tunerInspector
            default:
                idle
            }
            Spacer()
        }
        .padding(16)
        .navigationTitle("Inspector")
    }

    private var latticeInspector: some View {
        Group {
            if let info = latticeSelectionInfo() {
                inspectorHeader(title: info.label, subtitle: "Selected Node")
                inspectorRow(title: "Frequency", value: String(format: "%.3f Hz", info.hz))
                inspectorRow(title: "Cents vs ET", value: String(format: "%+.1f¢", info.cents))
                inspectorRow(title: "Axis Position", value: "e3 \(info.e3) • e5 \(info.e5)")
                if !info.monzo.isEmpty {
                    inspectorRow(title: "Monzo", value: info.monzoDescription)
                }
                actionRow(for: info.ref)
            } else {
                idle
            }
        }
    }

    private var tunerInspector: some View {
        let display = app.display
        let ratio = display.ratioText
        let cents = display.cents
        let hz = display.hz

        return Group {
            inspectorHeader(title: "Tuner Readout", subtitle: "Live")
            inspectorRow(title: "Ratio", value: ratio)
            inspectorRow(title: "Frequency", value: String(format: "%.3f Hz", hz))
            inspectorRow(title: "Cents", value: String(format: "%+.1f¢", cents))
            HStack {
                Button("Copy Ratio") { UIPasteboard.general.string = ratio }
                Button("Copy Hz") { UIPasteboard.general.string = String(format: "%.3f Hz", hz) }
                Button("Copy Cents") { UIPasteboard.general.string = String(format: "%+.1f¢", cents) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 6) {
            inspectorHeader(title: "Inspector", subtitle: "Ready")
            Text("Select a node to inspect.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func inspectorHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func inspectorRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    private func actionRow(for ref: RatioRef) -> some View {
        HStack {
            Button("Copy Ratio") { UIPasteboard.general.string = "\(ref.p)/\(ref.q)" }
            Button("Copy Hz") {
                let hz = RatioMath.foldToAudible(RatioMath.ratioToHz(p: ref.p, q: ref.q, octave: ref.octave, rootHz: app.rootHz, centsError: ref.centsError ?? 0))
                UIPasteboard.general.string = String(format: "%.3f Hz", hz)
            }
            Button("Copy Cents") {
                let hz = RatioMath.foldToAudible(RatioMath.ratioToHz(p: ref.p, q: ref.q, octave: ref.octave, rootHz: app.rootHz, centsError: ref.centsError ?? 0))
                let cents = RatioMath.centsFromET(freqHz: hz, refHz: app.rootHz)
                UIPasteboard.general.string = String(format: "%+.1f¢", cents)
            }
            Button("Add to Scale") { openBuilder(with: ref) }
            Button("Set as Root") {
                let hz = RatioMath.foldToAudible(RatioMath.ratioToHz(p: ref.p, q: ref.q, octave: ref.octave, rootHz: app.rootHz, centsError: ref.centsError ?? 0))
                app.rootHz = hz
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func openBuilder(with ref: RatioRef) {
        let payload = ScaleBuilderPayload(
            rootHz: app.rootHz,
            primeLimit: app.primeLimit,
            refs: [ref]
        )
        latticeStore.beginStaging()
        app.builderPayload = payload
    }

    private struct InspectorInfo {
        let ref: RatioRef
        let hz: Double
        let cents: Double
        let e3: Int
        let e5: Int
        let monzo: [Int:Int]

        var label: String { "\(ref.p)/\(ref.q)" }
        var monzoDescription: String {
            monzo.keys.sorted().map { "p\($0): \(monzo[$0] ?? 0)" }.joined(separator: "  ")
        }
    }

    private func latticeSelectionInfo() -> InspectorInfo? {
        if let c = latticeStore.selectionOrder.first ?? latticeStore.selected.first {
            let e3 = c.e3 + latticeStore.pivot.e3 + (latticeStore.axisShift[3] ?? 0)
            let e5 = c.e5 + latticeStore.pivot.e5 + (latticeStore.axisShift[5] ?? 0)
            let p = (e3 > 0 ? Int(pow(3.0, Double(e3))) : 1) * (e5 > 0 ? Int(pow(5.0, Double(e5))) : 1)
            let q = (e3 < 0 ? Int(pow(3.0, Double(-e3))) : 1) * (e5 < 0 ? Int(pow(5.0, Double(-e5))) : 1)
            let (cn, cd) = RatioMath.canonicalPQUnit(p, q)
            let hz = RatioMath.foldToAudible(RatioMath.ratioToHz(p: cn, q: cd, octave: 0, rootHz: app.rootHz, centsError: 0))
            let cents = RatioMath.centsFromET(freqHz: hz, refHz: app.rootHz)
            let ref = RatioRef(p: cn, q: cd, octave: 0, monzo: [3:e3, 5:e5])
            return InspectorInfo(ref: ref, hz: hz, cents: cents, e3: e3, e5: e5, monzo: [3:e3, 5:e5])
        }
        return nil
    }
}
#endif
