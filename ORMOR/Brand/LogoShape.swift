import SwiftUI

/// Parts of the reconstructed OR & MOR logo (see LogoPathData.swift).
struct LogoParts: OptionSet, Hashable {
    let rawValue: Int
    static let crest = LogoParts(rawValue: 1 << 0)
    static let arabic = LogoParts(rawValue: 1 << 1)
    static let latin = LogoParts(rawValue: 1 << 2)
    static let all: LogoParts = [.crest, .arabic, .latin]
}

/// The logo as a SwiftUI shape, aspect-fit inside its frame using the full 551 x 501 viewBox
/// so parts drawn separately stay aligned.
struct LogoShape: Shape {
    var parts: LogoParts = .all

    static let viewBox = CGSize(width: 551, height: 501)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.viewBox.width, rect.height / Self.viewBox.height)
        let offset = CGPoint(x: rect.midX - Self.viewBox.width * scale / 2,
                             y: rect.midY - Self.viewBox.height * scale / 2)
        let transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        var path = Path()
        if parts.contains(.crest) { path.addPath(LogoGeometry.crest, transform: transform) }
        if parts.contains(.arabic) { path.addPath(LogoGeometry.arabic, transform: transform) }
        if parts.contains(.latin) { path.addPath(LogoGeometry.latin, transform: transform) }
        return path
    }
}

/// Parsed logo paths in viewBox space, built once.
enum LogoGeometry {
    static let crest = parse(LogoPathData.crest)
    static let arabic = parse(LogoPathData.arabic)
    static let latin = parse(LogoPathData.latin)

    /// The SVG is drawn in potrace units with `translate(0 501) scale(.1 -.1)`.
    private static func parse(_ strings: [String]) -> Path {
        var path = Path()
        for d in strings {
            SVGPathParser.append(d, to: &path) { x, y in CGPoint(x: x * 0.1, y: 501 - y * 0.1) }
        }
        return path
    }
}

/// Minimal SVG path-data parser for the commands potrace emits (M m L l C c Z z).
enum SVGPathParser {
    static func append(_ d: String, to path: inout Path, map: (Double, Double) -> CGPoint) {
        var tokens: [Substring] = []
        var i = d.startIndex
        while i < d.endIndex {
            let c = d[i]
            if "MmLlCcZz".contains(c) {
                tokens.append(d[i...i]); i = d.index(after: i)
            } else if c == "-" || c == "." || c.isNumber {
                var j = d.index(after: i)
                while j < d.endIndex, d[j].isNumber || d[j] == "." || d[j] == "e" { j = d.index(after: j) }
                tokens.append(d[i..<j]); i = j
            } else {
                i = d.index(after: i)
            }
        }

        var index = 0
        var command: Character = "M"
        var current = (x: 0.0, y: 0.0)
        var start = current
        func number() -> Double {
            defer { index += 1 }
            return index < tokens.count ? Double(tokens[index]) ?? 0 : 0
        }
        while index < tokens.count {
            if let c = tokens[index].first, c.isLetter, tokens[index].count == 1 {
                command = c; index += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath(); current = start
                    continue
                }
            }
            switch command {
            case "M", "m":
                var x = number(), y = number()
                if command == "m" { x += current.x; y += current.y }
                current = (x, y); start = current
                path.move(to: map(x, y))
                command = command == "m" ? "l" : "L"  // implicit lineto after moveto
            case "L", "l":
                var x = number(), y = number()
                if command == "l" { x += current.x; y += current.y }
                current = (x, y)
                path.addLine(to: map(x, y))
            case "C", "c":
                var v = (0..<6).map { _ in number() }
                if command == "c" {
                    for k in 0..<6 { v[k] += k % 2 == 0 ? current.x : current.y }
                }
                path.addCurve(to: map(v[4], v[5]), control1: map(v[0], v[1]), control2: map(v[2], v[3]))
                current = (v[4], v[5])
            default:
                index += 1
            }
        }
    }
}
