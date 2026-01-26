import QuartzCore

enum TunerLockSheetGate {
    private static var ignoreUntil: CFTimeInterval = 0

    static func armCooldown(seconds: CFTimeInterval = 0.6) {
        ignoreUntil = CACurrentMediaTime() + seconds
    }

    static func shouldIgnoreOpen() -> Bool {
        CACurrentMediaTime() < ignoreUntil
    }
}
