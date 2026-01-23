//
//  TenneyLimitShapes.swift
//  Tenney
//

import SwiftUI

struct RegularPolygon: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        guard sides >= 3 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5
        let startAngle = -CGFloat.pi / 2
        let step = (2 * CGFloat.pi) / CGFloat(sides)

        var path = Path()
        for i in 0..<sides {
            let angle = startAngle + step * CGFloat(i)
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let leftTop = CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.20)
        let rightTop = CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.20)
        let leftMid = CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.62)
        let rightMid = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.62)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: top)
        path.addLine(to: leftTop)
        path.addLine(to: leftMid)
        path.addQuadCurve(to: bottom, control: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.maxY + rect.height * 0.05))
        path.addQuadCurve(to: rightMid, control: CGPoint(x: rect.maxX - rect.width * 0.5, y: rect.maxY + rect.height * 0.05))
        path.addLine(to: rightTop)
        path.closeSubpath()
        return path
    }
}

struct LimitShape: Shape {
    let bucket: TenneyLimitBucket

    func path(in rect: CGRect) -> Path {
        switch bucket {
        case .limit5:
            return Circle().path(in: rect)
        case .limit7:
            return RegularPolygon(sides: 3).path(in: rect)
        case .limit11:
            return Rectangle().path(in: rect)
        case .limit13:
            return DiamondShape().path(in: rect)
        case .limit17:
            return RegularPolygon(sides: 5).path(in: rect)
        case .limit19:
            return RegularPolygon(sides: 6).path(in: rect)
        case .limit23:
            return RegularPolygon(sides: 7).path(in: rect)
        case .limit29:
            return RegularPolygon(sides: 8).path(in: rect)
        case .limit31:
            return ShieldShape().path(in: rect)
        }
    }
}

func limitShapePath(bucket: TenneyLimitBucket, in rect: CGRect) -> Path {
    LimitShape(bucket: bucket).path(in: rect)
}

enum TenneyLimitPatternKind {
    case stroke
    case dots
}

enum TenneyLimitPattern {
    private static let unitPaths: [TenneyLimitBucket: Path] = {
        var paths: [TenneyLimitBucket: Path] = [:]

        // 7: diagonal hatch
        var hatch = Path()
        for x in stride(from: -0.4, through: 1.1, by: 0.28) {
            hatch.move(to: CGPoint(x: x, y: 0))
            hatch.addLine(to: CGPoint(x: x + 1.0, y: 1.0))
        }
        paths[.limit7] = hatch

        // 11: dot stipple
        var dots = Path()
        let dotRadius: CGFloat = 0.06
        for x in stride(from: 0.2, through: 0.8, by: 0.3) {
            for y in stride(from: 0.2, through: 0.8, by: 0.3) {
                let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                dots.addEllipse(in: rect)
            }
        }
        paths[.limit11] = dots

        // 13: cross hatch
        var cross = hatch
        for x in stride(from: -0.4, through: 1.1, by: 0.28) {
            cross.move(to: CGPoint(x: x, y: 1.0))
            cross.addLine(to: CGPoint(x: x + 1.0, y: 0.0))
        }
        paths[.limit13] = cross

        return paths
    }()

    static func kind(for bucket: TenneyLimitBucket) -> TenneyLimitPatternKind? {
        switch bucket {
        case .limit7, .limit13:
            return .stroke
        case .limit11:
            return .dots
        default:
            return nil
        }
    }

    static func path(bucket: TenneyLimitBucket, in rect: CGRect) -> Path? {
        guard let unit = unitPaths[bucket] else { return nil }
        let transform = CGAffineTransform(scaleX: rect.width, y: rect.height)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return unit.applying(transform)
    }
}
