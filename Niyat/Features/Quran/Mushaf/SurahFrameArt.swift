import SwiftUI

/// The drawing of a surah heading, in the manner of the illuminated headings of
/// the printed Madinah mushaf (Niyat's own vector drawing, not a copy):
/// a double-ruled band filled with interlaced strapwork, palmette finials at
/// its ends, a double-framed cartouche with ogee points for the name, and a
/// scalloped, double-ringed medallion on each side. In the page's colours;
/// sizes are fractions of the band's height.
struct SurahFrameArt {
    let geometry: SurahFrameGeometry
    let gold: Color
    let fill: Color
    let paper: Color

    private var h: CGFloat { geometry.height }
    private var line: CGFloat { max(0.6, h * 0.02) }

    func draw(in context: inout GraphicsContext) {
        drawBand(in: &context)
        drawStrapwork(in: &context)
        drawFinials(in: &context)
        drawCartouche(in: &context)
        for centre in geometry.medallions { drawMedallion(in: &context, at: centre) }
    }

    // MARK: Band

    /// Gilded ground inside a double rule: a heavy outer line, a fine inner one.
    private func drawBand(in context: inout GraphicsContext) {
        let band = Path(roundedRect: geometry.bounds, cornerRadius: 2)
        context.fill(band, with: .color(fill))
        context.fill(band, with: .color(gold.opacity(0.22)))
        context.stroke(band, with: .color(gold), lineWidth: line * 2.2)
        let rule = geometry.field.insetBy(dx: -h * 0.035, dy: -h * 0.035)
        context.stroke(Path(roundedRect: rule, cornerRadius: 1.5), with: .color(gold), lineWidth: line * 0.9)
    }

    // MARK: Strapwork

    /// Two vines woven round each other along the band, drawn as straps (a
    /// gold line with a ground-coloured core). Each loop they make holds a
    /// split palmette, and a scroll curls off every outer crest.
    private func drawStrapwork(in context: inout GraphicsContext) {
        let field = geometry.field
        var layer = context
        layer.clip(to: Path(field))
        let wave = h * 1.05
        let amplitude = field.height * 0.3
        let mid = geometry.midY
        let strap = StrokeStyle(lineWidth: line * 2.6, lineCap: .round, lineJoin: .round)
        let core = StrokeStyle(lineWidth: line * 1.0, lineCap: .round, lineJoin: .round)
        let thin = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        let half = field.width / 2
        for mirror in [1.0, -1.0] {
            let x = { (d: CGFloat) in geometry.bounds.midX + mirror * d }
            for phase in [0.0, Double.pi] {
                var vine = Path()
                for i in 0...Int(half / 1.5) {
                    let d = CGFloat(i) * 1.5
                    let y = mid + amplitude * CGFloat(sin(Double(d / wave) * 2 * .pi + phase))
                    if i == 0 { vine.move(to: CGPoint(x: x(d), y: y)) } else { vine.addLine(to: CGPoint(x: x(d), y: y)) }
                }
                layer.stroke(vine, with: .color(gold), style: strap)
                layer.stroke(vine, with: .color(fill), style: core)
            }
            // In each loop, a split palmette; on each crest, an outward scroll.
            var d = wave * 0.25
            var up = true
            while d < half {
                let centre = CGPoint(x: x(d), y: mid)
                palmette(in: &layer, at: centre, size: amplitude * 0.75, vertical: up ? -1 : 1)
                for vertical in [-1.0, 1.0] {
                    let crest = CGPoint(x: x(d), y: mid + vertical * amplitude)
                    layer.stroke(Self.scroll(from: crest, reach: mirror * wave * 0.22, rise: vertical * field.height * 0.12,
                                             curl: field.height * 0.07), with: .color(gold), style: thin)
                }
                d += wave / 2
                up.toggle()
            }
        }
    }

    /// Two leaves splitting from a stem, with a bead at their root.
    private func palmette(in context: inout GraphicsContext, at centre: CGPoint, size: CGFloat, vertical: CGFloat) {
        for side in [-1.0, 1.0] {
            let tip = CGPoint(x: centre.x + side * size * 0.55, y: centre.y + vertical * size * 0.7)
            context.fill(petal(from: CGPoint(x: centre.x, y: centre.y - vertical * size * 0.25), to: tip, width: size * 0.2),
                         with: .color(gold))
        }
        dot(in: &context, CGPoint(x: centre.x, y: centre.y - vertical * size * 0.3), size * 0.14)
    }

    // MARK: Finials

    /// A pointed palmette against each end of the band, pointing outwards.
    private func drawFinials(in context: inout GraphicsContext) {
        let field = geometry.field
        let mid = geometry.midY
        for (edge, direction) in [(field.minX, 1.0), (field.maxX, -1.0)] {
            let length = field.height * 0.85
            let base = CGPoint(x: edge + direction * length, y: mid)
            let point = CGPoint(x: edge + direction * h * 0.02, y: mid)
            var shape = Path()
            shape.move(to: point)
            shape.addCurve(to: base, control1: CGPoint(x: point.x + direction * length * 0.35, y: mid - field.height * 0.5),
                           control2: CGPoint(x: base.x, y: mid - field.height * 0.42))
            shape.addCurve(to: point, control1: CGPoint(x: base.x, y: mid + field.height * 0.42),
                           control2: CGPoint(x: point.x + direction * length * 0.35, y: mid + field.height * 0.5))
            shape.closeSubpath()
            context.fill(shape, with: .color(fill))
            context.fill(shape, with: .color(gold.opacity(0.22)))
            context.stroke(shape, with: .color(gold), lineWidth: line * 1.4)
            // A lily inside: a centre leaf pointing out, two leaves curving back, a bead at the root.
            let root = CGPoint(x: edge + direction * length * 0.68, y: mid)
            context.fill(petal(from: root, to: CGPoint(x: edge + direction * length * 0.2, y: mid), width: field.height * 0.08),
                         with: .color(gold))
            for side in [-1.0, 1.0] {
                context.fill(petal(from: root, to: CGPoint(x: edge + direction * length * 0.42, y: mid + side * field.height * 0.26),
                                   width: field.height * 0.06), with: .color(gold.opacity(0.85)))
            }
            dot(in: &context, root, field.height * 0.06)
        }
    }

    // MARK: Cartouche

    /// Straight top and bottom; each end swells and narrows to an ogee point.
    static func cartouchePath(_ rect: CGRect, tip: CGFloat) -> Path {
        let c = rect.height * 0.6
        let mid = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX + tip, y: mid),
                      control1: CGPoint(x: rect.maxX + c * 0.15, y: rect.minY),
                      control2: CGPoint(x: rect.maxX - tip * 0.2, y: mid - rect.height * 0.12))
        path.addCurve(to: CGPoint(x: rect.maxX - c, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX - tip * 0.2, y: mid + rect.height * 0.12),
                      control2: CGPoint(x: rect.maxX + c * 0.15, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX - tip, y: mid),
                      control1: CGPoint(x: rect.minX - c * 0.15, y: rect.maxY),
                      control2: CGPoint(x: rect.minX + tip * 0.2, y: mid + rect.height * 0.12))
        path.addCurve(to: CGPoint(x: rect.minX + c, y: rect.minY),
                      control1: CGPoint(x: rect.minX + tip * 0.2, y: mid - rect.height * 0.12),
                      control2: CGPoint(x: rect.minX - c * 0.15, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// A plain halo keeps the strapwork off; then two frames, with a band of
    /// beads between them, round the paper panel that holds the name.
    private func drawCartouche(in context: inout GraphicsContext) {
        let rect = geometry.cartouche
        let tip = geometry.tip
        let halo = Self.cartouchePath(rect.insetBy(dx: -h * 0.07, dy: -h * 0.07), tip: tip * 1.2)
        context.fill(halo, with: .color(fill))
        context.fill(halo, with: .color(gold.opacity(0.22)))
        context.stroke(halo, with: .color(gold), lineWidth: line)

        let outer = Self.cartouchePath(rect, tip: tip)
        let gap = h * 0.075
        let innerRect = rect.insetBy(dx: gap, dy: gap)
        let inner = Self.cartouchePath(innerRect, tip: tip * 0.75)
        context.fill(outer, with: .color(gold.opacity(0.35)))
        context.stroke(outer, with: .color(gold), lineWidth: line * 1.8)
        // Beads in the band between the frames, along the straight edges.
        let beadY = [rect.minY + gap / 2, rect.maxY - gap / 2]
        var x = innerRect.minX + innerRect.height * 0.5
        while x < innerRect.maxX - innerRect.height * 0.5 {
            for y in beadY { dot(in: &context, CGPoint(x: x, y: y), gap * 0.18) }
            x += gap * 0.9
        }
        context.fill(inner, with: .color(paper))
        context.stroke(inner, with: .color(gold), lineWidth: line * 1.1)
        // A trefoil beyond each point.
        for side in [-1.0, 1.0] {
            let px = side > 0 ? rect.maxX + tip * 1.55 : rect.minX - tip * 1.55
            for (dx, dy) in [(0.0, 0.0), (-0.05, -0.065), (-0.05, 0.065)] {
                dot(in: &context, CGPoint(x: px + side * h * dx, y: geometry.midY + h * dy), h * 0.024)
            }
        }
    }

    // MARK: Medallions

    /// Pointed lugs tie the medallion into the strapwork; a scalloped edge, a
    /// gilded ring and a paper centre for the text (`SurahFrame`).
    private func drawMedallion(in context: inout GraphicsContext, at centre: CGPoint) {
        let r = geometry.medallionRadius
        guard r > 2 else { return }
        for side in [-1.0, 1.0] {
            var lug = Path()
            lug.move(to: CGPoint(x: centre.x + side * r * 0.75, y: centre.y - r * 0.38))
            lug.addQuadCurve(to: CGPoint(x: centre.x + side * r * 1.45, y: centre.y),
                             control: CGPoint(x: centre.x + side * r * 1.25, y: centre.y - r * 0.32))
            lug.addQuadCurve(to: CGPoint(x: centre.x + side * r * 0.75, y: centre.y + r * 0.38),
                             control: CGPoint(x: centre.x + side * r * 1.25, y: centre.y + r * 0.32))
            context.fill(lug, with: .color(fill))
            context.fill(lug, with: .color(gold.opacity(0.4)))
            context.stroke(lug, with: .color(gold), lineWidth: line * 1.2)
        }
        let scallops = Self.scallopedCircle(centre: centre, radius: r, lobes: 18)
        context.fill(scallops, with: .color(gold.opacity(0.35)))
        context.fill(scallops, with: .color(fill.opacity(0.5)))
        context.stroke(scallops, with: .color(gold), lineWidth: line * 1.5)
        let ring = r * 0.8
        let ringPath = Path(ellipseIn: CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2))
        context.fill(ringPath, with: .color(paper))
        context.stroke(ringPath, with: .color(gold), lineWidth: line * 1.1)
        let fine = r * 0.72
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - fine, y: centre.y - fine, width: fine * 2, height: fine * 2)),
                       with: .color(gold.opacity(0.5)), lineWidth: line * 0.6)
    }

    /// A circle whose edge is a row of small outward arcs.
    static func scallopedCircle(centre: CGPoint, radius: CGFloat, lobes: Int) -> Path {
        var path = Path()
        let step = 2 * Double.pi / Double(lobes)
        let inner = radius * 0.93
        for i in 0..<lobes {
            let a0 = Double(i) * step, a1 = a0 + step, am = a0 + step / 2
            let start = CGPoint(x: centre.x + cos(a0) * inner, y: centre.y + sin(a0) * inner)
            let end = CGPoint(x: centre.x + cos(a1) * inner, y: centre.y + sin(a1) * inner)
            let bulge = CGPoint(x: centre.x + cos(am) * radius * 1.07, y: centre.y + sin(am) * radius * 1.07)
            if i == 0 { path.move(to: start) }
            path.addQuadCurve(to: end, control: bulge)
        }
        path.closeSubpath()
        return path
    }

    // MARK: Pieces

    /// A stem that sweeps out by `reach` and `rise`, then curls into a spiral
    /// that ends with a small inward turn, the way a drawn scroll does.
    static func scroll(from start: CGPoint, reach: CGFloat, rise: CGFloat, curl: CGFloat) -> Path {
        let end = CGPoint(x: start.x + reach, y: start.y + rise)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: start.x + reach * 0.2, y: end.y))
        let centre = CGPoint(x: end.x, y: end.y - (rise > 0 ? curl : -curl))
        let startAngle: Angle = rise > 0 ? .degrees(90) : .degrees(-90)
        let clockwise = (reach > 0) == (rise > 0)
        let turn: Double = clockwise ? -270 : 270
        path.addArc(center: centre, radius: curl, startAngle: startAngle, endAngle: startAngle + .degrees(turn), clockwise: clockwise)
        let inner = curl * 0.45
        let endAngle = startAngle + .degrees(turn)
        let innerCentre = CGPoint(x: centre.x + cos(endAngle.radians) * (curl - inner),
                                  y: centre.y + sin(endAngle.radians) * (curl - inner))
        path.addArc(center: innerCentre, radius: inner, startAngle: endAngle,
                    endAngle: endAngle + .degrees(clockwise ? -180 : 180), clockwise: clockwise)
        return path
    }

    private func petal(from base: CGPoint, to tip: CGPoint, width: CGFloat) -> Path {
        let length = max(hypot(tip.x - base.x, tip.y - base.y), 0.001)
        let normal = CGPoint(x: -(tip.y - base.y) / length * width, y: (tip.x - base.x) / length * width)
        let middle = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
        var path = Path()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: middle.x + normal.x, y: middle.y + normal.y))
        path.addQuadCurve(to: base, control: CGPoint(x: middle.x - normal.x, y: middle.y - normal.y))
        return path
    }

    private func dot(in context: inout GraphicsContext, _ centre: CGPoint, _ radius: CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(gold))
    }
}
