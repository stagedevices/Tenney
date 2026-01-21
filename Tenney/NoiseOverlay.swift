import SwiftUI

struct NoiseOverlay: View {
    let seed: Int
    var opacity: Double = 0.05
    var density: Int = 120

    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed))
            let step = max(1, Int(min(size.width, size.height) / CGFloat(density)))
            let columns = max(1, Int(size.width) / step)
            let rows = max(1, Int(size.height) / step)

            for y in 0...rows {
                for x in 0...columns {
                    let value = Double.random(in: 0.0...1.0, using: &generator)
                    let alpha = opacity * (0.35 + value * 0.65)
                    let rect = CGRect(
                        x: CGFloat(x * step),
                        y: CGFloat(y * step),
                        width: CGFloat(step),
                        height: CGFloat(step)
                    )
                    context.fill(Path(rect), with: .color(Color.black.opacity(alpha)))
                }
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xdecafbadcafebabe : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}
