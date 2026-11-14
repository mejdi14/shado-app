import SwiftUI
import SpriteKit
import ImageIO

// MARK: Voice guide: the painted head in section of Voice Workshop by Fabio Angela (github.com/MithrilMan/voice-workshop, Apache-2.0),
// bundled unmodified as mac/voice-workshop-head.jpg (licence and notice in mac/VOICE-WORKSHOP-LICENSE.txt, copied into the app by Build Mac App.command).
// The cut into parts, the simplified motion and the glowing air are our own; no acoustic model runs.
// Coordinates are the painting's pixels (1024 × 1536, y down, 51.2 px per cm, glottis at about (367, 1176)).

enum VH {
    static let teal = Color(red: 0.165, green: 0.83, blue: 0.74), amber = Color(red: 0.95, green: 0.7, blue: 0.24), panel = Color(red: 0.035, green: 0.047, blue: 0.067)
    static let view = CGRect(x: 40, y: 70, width: 880, height: 1320)
    @MainActor static var art: HeadArt?

    static func pts(_ v: [(Double, Double)]) -> [CGPoint] { v.map { CGPoint(x: $0.0, y: $0.1) } }
    static func ramp(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    static func box(_ p: CGPoint, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ e: Double) -> Double { ramp(x0 - e, x0, p.x) * (1 - ramp(x1, x1 + e, p.x)) * ramp(y0 - e, y0, p.y) * (1 - ramp(y1, y1 + e, p.y)) }
    static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    static func rotate(_ p: CGPoint, _ c: CGPoint, _ a: Double) -> CGPoint { let dx = p.x - c.x, dy = p.y - c.y; return CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a)) }
    static func larynx(_ semis: Double) -> Double { min(1.2, max(-1.2, semis * 0.12)) }
    static func note(_ hz: Double) -> String {
        let m = Int((69 + 12 * log2(hz / 440)).rounded())
        return ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][((m % 12) + 12) % 12] + "\(m / 12 - 1)"
    }

    // Everything below the mouth's air and in front of the throat's air moves (jaw, tongue, lower lip, larynx); the rest of the head is rigid.
    static let lowerBand = pts([(371, 740), (385, 710), (420, 687), (440, 677), (480, 667), (520, 666), (560, 676), (600, 694), (640, 719), (660, 735), (680, 747), (700, 759), (720, 775), (740, 766), (760, 770), (780, 750), (800, 751), (1024, 751), (1024, 1536), (366, 1536), (366, 1176), (367, 1160), (370, 1120), (371, 1080), (362, 1040), (353, 1000), (354, 980), (349, 940), (344, 900), (343, 860), (347, 820), (354, 780)])
    static let lowerRect = CGRect(x: 330, y: 600, width: 694, height: 936)
    static let hull = pts([(326, 622), (440, 624), (520, 618), (600, 636), (650, 664), (690, 698), (722, 738), (800, 740), (792, 760), (766, 792), (748, 905), (640, 935), (520, 985), (420, 1015), (402, 1195), (326, 1195)])
    static let nasal = pts([(346, 627), (364, 584), (405, 548), (471, 525), (563, 515), (655, 520), (732, 538), (799, 566), (847, 602)])
    static let route = pts([(367, 1176), (370, 1120), (371, 1080), (362, 1040), (353, 1000), (349, 940), (344, 900), (343, 860), (347, 820), (354, 780), (371, 740), (395, 702), (440, 677), (480, 667), (520, 666), (560, 676), (600, 694), (640, 719), (680, 747), (720, 770), (760, 770), (795, 752)])
    // The air's centre line from the glottis (s = 0) to the lips (s = 1), evenly resampled, with its normal pointing to the moving side.
    static let line: [(c: CGPoint, n: CGVector, s: Double)] = {
        var len = [0.0]
        for i in 1..<route.count { len.append(len[i - 1] + dist(route[i - 1], route[i])) }
        let total = len.last!, count = 64
        let c = (0..<count).map { k -> CGPoint in
            let at = total * Double(k) / Double(count - 1)
            let i = min(route.count - 2, max(0, (len.lastIndex { $0 <= at } ?? 0)))
            return mix(route[i], route[i + 1], (at - len[i]) / max(0.001, len[i + 1] - len[i]))
        }
        return c.indices.map { k in
            let a = c[max(0, k - 1)], b = c[min(count - 1, k + 1)], d = max(0.001, dist(a, b))
            return (c[k], CGVector(dx: -(b.y - a.y) / d, dy: (b.x - a.x) / d), Double(k) / Double(count - 1))
        }
    }()
    static func oral(_ s: Double) -> Double { ramp(0.42, 0.58, s) }

    static func fieldColor(_ s: Double, _ p: HeadPose, _ phase: Double) -> Color {
        var pulse = 0.0
        for j in 0..<2 { let d = s - (phase + Double(j) * 0.5).truncatingRemainder(dividingBy: 1); pulse = max(pulse, exp(-d * d / 0.0035)) }
        pulse *= p.voice * (0.4 + 0.6 * p.breath)
        let warm = pow(cos(s * .pi / 2), 2) * p.voice * (0.35 + 0.65 * p.breath), glow = 0.3 + 0.55 * p.breath
        return Color(red: min(1, 0.02 + (0.165 + 0.785 * warm) * glow + 0.5 * pulse), green: min(1, 0.027 + (0.83 - 0.13 * warm) * glow + 0.25 * pulse), blue: min(1, 0.047 + (0.74 - 0.5 * warm) * glow + 0.15 * pulse))
    }

    // Under the painting: the air, lit along the tract (pressure strongest at the voice box), pulses travelling up at a rate that follows pitch, and drifting air.
    static func drawAir(_ g: GraphicsContext, _ size: CGSize, _ p: HeadPose, _ clock: Double) {
        let k = size.width / view.width
        func m(_ q: CGPoint) -> CGPoint { CGPoint(x: (q.x - view.minX) * k, y: (q.y - view.minY) * k) }
        var hullPath = Path(); hullPath.addLines(hull.map { m(p.stretch($0)) }); hullPath.closeSubpath()
        var gc = g
        gc.clip(to: hullPath)
        gc.fill(hullPath, with: .color(Color(red: 0.02, green: 0.027, blue: 0.047)))
        let tops = line.map { m(p.stretch(CGPoint(x: $0.c.x - $0.n.dx * (30 + 25 * oral($0.s)), y: $0.c.y - $0.n.dy * (30 + 25 * oral($0.s))))) }
        let bots = line.map { m(p.warp(CGPoint(x: $0.c.x + $0.n.dx * (40 + 30 * oral($0.s)), y: $0.c.y + $0.n.dy * (40 + 30 * oral($0.s))))) }
        let phase = clock * 1.4 * pow(2, p.semis / 12)
        for i in 0..<(line.count - 1) {
            var q = Path(); q.addLines([tops[i], tops[i + 1], bots[i + 1], bots[i]]); q.closeSubpath()
            let c = fieldColor(line[i].s, p, phase)
            gc.fill(q, with: .color(c)); gc.stroke(q, with: .color(c), lineWidth: 0.8)
        }
        if p.voice > 0.02 {
            let c = m(p.stretch(CGPoint(x: 367, y: 1166))), r = (9 + 5 * p.breath) * (0.85 + 0.15 * sin(clock * 2 * .pi * 6 * pow(2, p.semis / 12))) * k * 2
            gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.6, width: 2 * r, height: 1.2 * r)), with: .radialGradient(Gradient(colors: [amber.opacity(0.9 * p.voice), amber.opacity(0)]), center: c, startRadius: 0, endRadius: r))
        }
        guard p.breath > 0.04 else { return }
        for j in 0..<30 {
            let s = (Double(j) * 0.618034 + clock * (0.12 + 0.45 * p.breath)).truncatingRemainder(dividingBy: 1), lat = Double((j * 37) % 11) / 10
            let x = s * Double(line.count - 1), i = min(line.count - 2, Int(x)), f = x - Double(i)
            let c = mix(mix(tops[i], tops[i + 1], f), mix(bots[i], bots[i + 1], f), 0.3 + 0.35 * lat)
            gc.fill(Path(ellipseIn: CGRect(x: c.x - 1.1, y: c.y - 1.1, width: 2.2, height: 2.2)), with: .color(.white.opacity(min(0.85, p.breath) * sin(.pi * s))))
        }
    }

    // Over the painting: the nose lights up for nasal sounds, and labelled markers follow the parts.
    static func drawMarks(_ g: GraphicsContext, _ size: CGSize, _ p: HeadPose) {
        let k = size.width / view.width
        func m(_ q: CGPoint) -> CGPoint { CGPoint(x: (q.x - view.minX) * k, y: (q.y - view.minY) * k) }
        if p.nasal > 0.02 {
            var path = Path(); path.addLines(nasal.map(m))
            g.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.stroke(path, with: .color(teal.opacity(0.5 * p.nasal)), style: StrokeStyle(lineWidth: 34 * k, lineCap: .round, lineJoin: .round))
            }
        }
        let lipTop = CGPoint(x: 792, y: 746), lipLow = p.warp(CGPoint(x: 784, y: 796))
        let marks: [(String, CGPoint, CGVector, Bool)] = [
            ("velum", CGPoint(x: 392, y: 652), CGVector(dx: -4, dy: -12), false),
            ("tongue", p.warp(CGPoint(x: 505, y: 742)), CGVector(dx: 0, dy: -12), false),
            ("tip", p.warp(CGPoint(x: 652, y: 780)), CGVector(dx: -12, dy: -11), false),
            ("teeth", CGPoint(x: 712, y: 752), CGVector(dx: 4, dy: -13), false),
            ("lips", CGPoint(x: (lipTop.x + lipLow.x) / 2 + 18, y: (lipTop.y + lipLow.y) / 2), CGVector(dx: 17, dy: 0), false),
            ("jaw", p.warp(CGPoint(x: 770, y: 975)), CGVector(dx: 15, dy: 0), false),
            ("larynx", p.warp(CGPoint(x: 432, y: 1122)), CGVector(dx: 19, dy: 0), true),
        ]
        for (name, q, off, warm) in marks {
            let c = m(q), col = warm ? amber : teal, ring = CGRect(x: c.x - 3.8, y: c.y - 3.8, width: 7.6, height: 7.6)
            g.fill(Path(ellipseIn: ring), with: .color(panel.opacity(0.8)))
            g.stroke(Path(ellipseIn: ring), with: .color(col), lineWidth: 1.4)
            g.fill(Path(ellipseIn: CGRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)), with: .color(col))
            let label = g.resolve(Text(name).font(.system(size: 8.5, weight: .medium)).foregroundColor(.white.opacity(0.92)))
            let ts = label.measure(in: CGSize(width: 120, height: 20)), at = CGPoint(x: c.x + off.dx + (off.dy == 0 ? ts.width / 2 - 6 : 0), y: c.y + off.dy)
            let tag = Path(roundedRect: CGRect(x: at.x - ts.width / 2 - 4, y: at.y - ts.height / 2 - 1.5, width: ts.width + 8, height: ts.height + 3), cornerRadius: 4)
            g.fill(tag, with: .color(panel.opacity(0.78)))
            g.stroke(tag, with: .color(col.opacity(0.4)), lineWidth: 0.6)
            g.draw(label, at: at, anchor: .center)
        }
    }
}

// MARK: Pose: jaw opening (0 closed … 1 wide, 0.25 as painted), shifts in painting pixels, larynx height in cm (+ up), the dot face's lip gap in painting pixels

struct HeadPose: Equatable {
    var jaw = 0.25, tongue = CGVector.zero, tip = CGVector.zero, lip = CGVector.zero
    var larynx = 0.0, voice = 0.0, breath = 0.0, nasal = 0.0, semis = 0.0, gap = 0.0
    static let joint = CGPoint(x: 327.7, y: 614.4), bend = 819.0, body0 = CGPoint(x: 495, y: 830), tip0 = CGPoint(x: 660, y: 782), lip0 = CGPoint(x: 748, y: 835)
    var k: Double { 1 - larynx / 7 }

    mutating func shape(_ a: Artic) {
        jaw = a.jaw
        tongue = CGVector(dx: (a.front - 0.5) * 50, dy: -(a.high - 0.35) * 75)
        tip = CGVector(dx: a.tipUp * 4 + a.tipFront * 15, dy: -a.tipUp * 55 - a.tipFront * 6)
        lip = CGVector(dx: -a.labio * 12, dy: -a.close * 30 - a.labio * 24)
        voice = a.voice; nasal = a.velum * a.voice
        gap = max(0, 12 + 88 * a.jaw - 40 * a.close - 30 * a.labio)
    }
    mutating func ah(_ amount: Double) { jaw = 0.25 + 0.4 * amount; tongue = CGVector(dx: -14 * amount, dy: 20 * amount); gap = 70 * amount }

    // The throat below the bend stretches or shortens as the larynx moves.
    func stretch(_ p: CGPoint) -> CGPoint { p.y > Self.bend ? CGPoint(x: p.x, y: Self.bend + (p.y - Self.bend) * k) : p }

    // Where a point of the moving part is now: the jaw turns about its joint (fully from the chin's bone forward), the tongue body follows by
    // three quarters and shifts with the vowel, the tip and the lower lip move locally, and the teeth below the tip are kept out of the tongue's moves.
    func warp(_ p: CGPoint) -> CGPoint {
        let th = 14 * Double.pi / 180 * (jaw - 0.25)
        let wj = VH.ramp(522, 676, p.x) * (1 - VH.ramp(1100, 1160, p.y))
        let keep = 1 - VH.box(p, 636, 722, 806, 925, 14)
        let wb = (1 - VH.ramp(110, 230, VH.dist(p, Self.body0))) * keep
        let wt = (1 - VH.ramp(25, 140, VH.dist(p, Self.tip0))) * (1 - VH.ramp(670, 695, p.x)) * keep
        let wl = (1 - VH.ramp(25, 95, VH.dist(p, Self.lip0))) * VH.ramp(712, 730, p.x)
        let b0 = VH.rotate(Self.body0, Self.joint, th * 0.75)
        var q = VH.rotate(p, Self.joint, th * wj)
        q.x += ((b0.x - Self.body0.x) * (1 - wj) + tongue.dx) * wb + tip.dx * wt + lip.dx * wl
        q.y += ((b0.y - Self.body0.y) * (1 - wj) + tongue.dy) * wb + tip.dy * wt + lip.dy * wl
        return stretch(q)
    }
}

// MARK: Painting: background and airway made transparent, then cut into the rigid head (above and below the bend) and the moving part

final class HeadArt: @unchecked Sendable {
    let top: CGImage, low: CGImage, lower: CGImage

    init?() {
        let w = 1024, h = 1536, n = w * h
        guard let url = Bundle.main.url(forResource: "voice-workshop-head", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(source, 0, nil),
              img.width == w, img.height == h, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: n * 4)
        func level(_ i: Int) -> UInt8 { max(px[4 * i], px[4 * i + 1], px[4 * i + 2]) }
        var state = [UInt8](repeating: 0, count: n), clear = [Bool](repeating: false, count: n), stack: [Int] = [], comp: [Int] = []
        for i in 0..<n where level(i) < 40 { state[i] = 1 }
        func flood(_ seed: Int) {
            comp.removeAll(keepingCapacity: true)
            guard state[seed] == 1 else { return }
            state[seed] = 2; stack.append(seed)
            while let i = stack.popLast() {
                comp.append(i)
                let x = i % w
                if x > 0, state[i - 1] == 1 { state[i - 1] = 2; stack.append(i - 1) }
                if x < w - 1, state[i + 1] == 1 { state[i + 1] = 2; stack.append(i + 1) }
                if i >= w, state[i - w] == 1 { state[i - w] = 2; stack.append(i - w) }
                if i + w < n, state[i + w] == 1 { state[i + w] = 2; stack.append(i + w) }
            }
        }
        for x in 0..<w { for i in [x, n - w + x] { flood(i); for j in comp { clear[j] = true } } }
        for y in 0..<h { for i in [y * w, y * w + w - 1] { flood(i); for j in comp { clear[j] = true } } }
        for i in 0..<n where state[i] == 1 { flood(i); if comp.count > 2000 { for j in comp { clear[j] = true } } }
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let i = y * w + x
            guard !clear[i], clear[i - 1] || clear[i + 1] || clear[i - w] || clear[i + w] else { continue }
            let a = min(1, max(0, (Double(level(i)) - 25) / 55))
            for c in 0..<4 { px[4 * i + c] = UInt8(Double(px[4 * i + c]) * a) }
        } }
        for i in 0..<n where clear[i] { for c in 0..<4 { px[4 * i + c] = 0 } }
        guard let masked = ctx.makeImage(),
              let top = HeadArt.cut(masked, CGRect(x: 0, y: 0, width: 1024, height: HeadPose.bend), keep: nil, drop: VH.lowerBand),
              let low = HeadArt.cut(masked, CGRect(x: 0, y: HeadPose.bend, width: 1024, height: 1536 - HeadPose.bend), keep: nil, drop: VH.lowerBand),
              let lower = HeadArt.cut(masked, VH.lowerRect, keep: VH.lowerBand, drop: nil) else { return nil }
        self.top = top; self.low = low; self.lower = lower
    }

    static func cut(_ img: CGImage, _ r: CGRect, keep: [CGPoint]?, drop: [CGPoint]?, scale: CGFloat = 0.5) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: Int((r.width * scale).rounded()), height: Int((r.height * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func path(_ q: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.addLines(between: q.map { CGPoint(x: $0.x, y: 1536 - $0.y) }); p.closeSubpath(); return p }
        c.interpolationQuality = .high
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -r.minX, y: -(1536 - r.maxY))
        if let keep { c.addPath(path(keep)); c.clip() }
        if let drop { c.addRect(CGRect(x: -10, y: -10, width: 1100, height: 1600)); c.addPath(path(drop)); c.clip(using: .evenOdd) }
        c.draw(img, in: CGRect(x: 0, y: 0, width: 1024, height: 1536))
        return c.makeImage()
    }
}

// MARK: Scene: the rigid head as two sprites (the lower one shortens with the larynx), the moving part as a warped sprite under them

final class HeadScene: SKScene {
    let top: SKSpriteNode, low: SKSpriteNode, lower: SKSpriteNode
    let grid = SKWarpGeometryGrid(columns: 22, rows: 28)
    var last: HeadPose?

    init(_ art: HeadArt) {
        func sprite(_ img: CGImage, _ w: CGFloat, _ h: CGFloat) -> SKSpriteNode { let t = SKTexture(cgImage: img); t.filteringMode = .linear; return SKSpriteNode(texture: t, size: CGSize(width: w, height: h)) }
        let r = VH.lowerRect, b = HeadPose.bend, v = VH.view
        top = sprite(art.top, 1024, b); low = sprite(art.low, 1024, 1536 - b); lower = sprite(art.lower, r.width, r.height)
        super.init(size: v.size)
        scaleMode = .aspectFit; backgroundColor = .clear
        top.anchorPoint = CGPoint(x: 0, y: 1); top.position = CGPoint(x: -v.minX, y: v.maxY); top.zPosition = 1
        low.anchorPoint = CGPoint(x: 0, y: 1); low.position = CGPoint(x: -v.minX, y: v.maxY - b); low.zPosition = 1
        lower.anchorPoint = .zero; lower.position = CGPoint(x: r.minX - v.minX, y: v.maxY - r.maxY); lower.subdivisionLevels = 1
        [lower, low, top].forEach(addChild)
    }
    required init?(coder: NSCoder) { nil }

    func apply(_ pose: HeadPose) {
        guard pose != last else { return }
        last = pose
        low.yScale = pose.k
        let r = VH.lowerRect
        let dst = (0..<grid.vertexCount).map { i -> SIMD2<Float> in
            let s = grid.sourcePosition(at: i)
            let q = pose.warp(CGPoint(x: r.minX + Double(s.x) * r.width, y: r.maxY - Double(s.y) * r.height))
            return SIMD2(Float((q.x - r.minX) / r.width), Float((r.maxY - q.y) / r.height))
        }
        lower.warpGeometry = grid.replacingByDestinationPositions(positions: dst)
    }
}

// MARK: Dot face: the head from outside, in dots, the way Dither Veil by React Bits (reactbits.dev/animations/dither-veil) dithers a picture:
// its Floyd–Steinberg error diffusion on serpentine rows, tone curve (contrast 1.15, gamma 1.6) and paper colour, rewritten here without its pointer effects.
// The grey picture is mac/voice-dot-head.png, drawn by mac/make_dot_head.py: one pixel per dot, its outline traced from the painting so both heads line up.
// To open the mouth, the dots below the mouth line turn about the jaw joint. The turn fades out towards the ear, the throat and the mouth corner,
// the dots keep their place on the skin, and the gap that opens between the lips stays dark.

final class DotHead {
    static let cols = 156, rows = 232, cell = 1320.0 / 232, x0 = 40 - (156 * 1320.0 / 232 - 880) / 2, y0 = 70.0
    static let corner = CGPoint(x: 705, y: 778), along = CGVector(dx: 0.99746, dy: -0.07125), reach = 508.0
    static let shared = DotHead()
    let rest: [UInt8]
    private var gap = -1.0, image: CGImage?

    init?() {
        let w = Self.cols, h = Self.rows
        guard let url = Bundle.main.url(forResource: "voice-dot-head", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(source, 0, nil), img.width == w, img.height == h else { return nil }
        let space = img.colorSpace.flatMap { $0.model == .monochrome ? $0 : nil } ?? CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = ctx.data else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h)
        var v = (0..<(w * h)).map { pow(min(1, max(0, (Double(px[$0]) / 255 - 0.5) * 1.15 + 0.5)), 1.6) }
        var bits = [UInt8](repeating: 0, count: w * h)
        let kernel: [(Int, Int, Double)] = [(1, 0, 7.0 / 16), (-1, 1, 3.0 / 16), (0, 1, 5.0 / 16), (1, 1, 1.0 / 16)]
        for y in 0..<h {
            let dir = y & 1 == 1 ? -1 : 1
            for i in 0..<w {
                let x = dir > 0 ? i : w - 1 - i, p = y * w + x, on = v[p] >= 0.5, err = v[p] - (on ? 1 : 0)
                bits[p] = on ? 1 : 0
                for (dx, dy, k) in kernel { let nx = x + dx * dir, ny = y + dy; if nx >= 0, nx < w, ny < h { v[ny * w + nx] += err * k } }
            }
        }
        rest = bits
    }

    // How much of the jaw's turn a point of the resting picture takes: none above the mouth line, all of it at the chin.
    static func weight(_ p: CGPoint) -> Double {
        let base = VH.ramp(430, 700, p.x) * (1 - VH.ramp(1120, 1260, p.y))
        if base == 0 { return 0 }
        let vx = p.x - corner.x, vy = p.y - corner.y, ahead = vx * along.dx + vy * along.dy, below = vy * along.dx - vx * along.dy
        if ahead > 0.16 * abs(below) { return below >= 0 ? base * VH.ramp(0, 170, hypot(vx, vy)) : 0 }
        let a = atan2(below, ahead)
        return base * VH.ramp(0, 170, hypot(vx, vy)) * (1 - VH.ramp(0.55 * .pi, 1.45 * .pi, a >= 0 ? a : a + 2 * .pi))
    }

    // The dots with the lips `gap` painting pixels apart. Each dot of the moving area looks up where it came from: a point that turned by
    // angle × weight about the joint, found by bisection along its arc. Where no such point exists the mouth is open, and the dot stays dark.
    func image(_ gap: Double) -> CGImage? {
        let g = min(104, max(0, gap)).rounded()
        if g == self.gap { return image }
        self.gap = g
        let w = Self.cols, h = Self.rows, k = Self.cell, th = g / Self.reach, j = HeadPose.joint
        var bits = rest
        if th > 0 {
            for y in 86..<212 { for x in 69..<w {
                let q = CGPoint(x: Self.x0 + (Double(x) + 0.5) * k, y: Self.y0 + (Double(y) + 0.5) * k)
                if Self.weight(q) == 0 { continue }
                let dx = q.x - j.x, dy = q.y - j.y
                func back(_ a: Double) -> CGPoint { let s = a - a * a * a / 6, c = 1 - a * a / 2 + a * a * a * a / 24; return CGPoint(x: j.x + dx * c + dy * s, y: j.y - dx * s + dy * c) }
                var lo = 0.0, hi = th
                for _ in 0..<10 { let mid = (lo + hi) / 2; if th * Self.weight(back(mid)) > mid { lo = mid } else { hi = mid } }
                let phi = (lo + hi) / 2, p = back(phi), sx = Int(((p.x - Self.x0) / k).rounded(.down)), sy = Int(((p.y - Self.y0) / k).rounded(.down))
                let found = abs(th * Self.weight(p) - phi) * hypot(dx, dy) < 0.6 * k && sx >= 0 && sx < w && sy >= 0 && sy < h
                bits[y * w + x] = found ? rest[sy * w + sx] : 0
            } }
        }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) where bits[i] == 1 { rgba[4 * i] = 244; rgba[4 * i + 1] = 241; rgba[4 * i + 2] = 234; rgba[4 * i + 3] = 255 }
        image = CGDataProvider(data: Data(rgba) as CFData).flatMap { CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent) }
        return image
    }
}

// MARK: View

struct VoiceHeadGuide: View {
    @EnvironmentObject var t: VoiceTrainingStore
    @AppStorage("voice-head") private var shown = true
    @AppStorage("voice-head-inside") private var inside = false
    @State private var scene: HeadScene?
    var dots: DotHead? { DotHead.shared }
    @State private var missing = false
    @State private var line = MouthTimeline()
    var active: Bool { t.playing || t.playingTake || t.recording }
    var exampleText: String? { t.exercise.isTone ? nil : (t.exampleContrast ? t.exercise.contrast : t.exercise.spoken) }
    var lineKey: String { "\(exampleText ?? "")|\(String(format: "%.2f", t.player?.duration ?? t.exercise.duration))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Voice guide", systemImage: "waveform.circle").font(.system(size: 12, weight: .semibold))
                Spacer()
                if shown, dots != nil { Button(inside ? "Dot face" : "Look inside") { inside.toggle() }.buttonStyle(PillStyle(compact: true)).help(inside ? "Cover the head with the dot face" : "Show the painted head in section, with the air, tongue and larynx") }
                Button(shown ? "Hide" : "Show") { shown.toggle() }.buttonStyle(PillStyle(compact: true)).help(shown ? "Hide the voice guide" : "Show what the voice box, air and mouth are doing")
            }
            if shown {
                if missing {
                    Text("The head picture is missing. Rebuild the Mac app with Build Mac App.command.").font(.system(size: 11)).foregroundStyle(Color.warn)
                } else {
                    TimelineView(.animation(paused: !active)) { tl in
                        let clock = tl.date.timeIntervalSinceReferenceDate, now = current()
                        let _ = scene?.apply(now.pose)
                        HStack(alignment: .top, spacing: 0) {
                            ZStack {
                                if let face = inside ? nil : dots?.image(now.pose.gap) {
                                    Image(decorative: face, scale: 1).interpolation(.none).resizable().frame(width: 234, height: 348)
                                } else {
                                    Canvas { g, size in VH.drawAir(g, size, now.pose, clock) }
                                    if let scene { SpriteView(scene: scene, preferredFramesPerSecond: active ? 60 : 10, options: [.allowsTransparency]) } else { ProgressView().controlSize(.small) }
                                    Canvas { g, size in VH.drawMarks(g, size, now.pose) }
                                }
                            }
                            .frame(width: 232, height: 348)
                            .accessibilityElement().accessibilityLabel(inside || dots == nil ? "Side view of a head in section. The air from the voice box to the lips glows with the voice, and the larynx rises and falls with pitch." : "Side view of a head drawn in white dots, facing right. The jaw and lips open and close with the sounds.")
                            info(now).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(VH.panel))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VH.teal.opacity(0.25)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text("A teaching picture, not a scan or simulation of your vocal tract. Examples follow the target and each sound roughly; while you record or replay, it shows only your pitch and loudness, not your mouth. Head painting from Voice Workshop by Fabio Angela (Apache-2.0); the dot look follows Dither Veil by React Bits.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: "\(shown) \(inside)") { if shown { await load() } }
        .task(id: lineKey) {
            guard let text = exampleText else { line = MouthTimeline(); return }
            let phrase = Phrase(start: 0, end: t.player?.duration ?? t.exercise.duration, text: text)
            let next = await Task.detached(priority: .userInitiated) { MouthTimeline(phrase) }.value
            if !Task.isCancelled { line = next }
        }
    }

    func load() async {
        guard inside || dots == nil, scene == nil, !missing else { return }
        if let art = VH.art { scene = HeadScene(art); return }
        if let art = await Task.detached(priority: .userInitiated, operation: { HeadArt() }).value { VH.art = art; scene = HeadScene(art) } else { missing = true }
    }

    // What drives the head now: the example's target while it plays, your microphone frames while you record or replay, otherwise rest.
    func current() -> (pose: HeadPose, seg: MouthSeg?, hz: Double?) {
        var p = HeadPose()
        let ex = t.exercise, skill = t.technique
        if t.playing, let player = t.player {
            let d = max(0.1, player.duration), time = player.currentTime, f = min(1, time / d)
            let pattern = t.exampleContrast ? ex.contrastPattern : ex.pattern
            p.semis = skill.usesPitch ? pattern.value(f) : 0
            p.larynx = VH.larynx(p.semis)
            if ex.isTone {
                let edge = max(0, min(1, min(time / 0.08, (d - time) / 0.08)))
                let envelope = skill == .energy ? 0.25 + (pattern.value(f) + 3) / 6 * 0.65 : skill == .rhythm ? trainingEnvelope(ex, skill, f) : 0.65
                p.ah(edge); p.voice = edge; p.breath = min(1, envelope / 0.9) * edge
                return (p, nil, 180 * pow(2, p.semis / 12))
            }
            let seg = line.seg(time)
            p.shape(line.artic(time))
            var energy = 0.75
            if skill == .stress || skill == .rhythm || (skill == .energy && !ex.units.isEmpty) {
                energy = 0.15 + 0.85 * trainingEnvelope(ex, skill, f, strong: t.exampleContrast ? ex.contrastStrong : ex.strong)
            }
            if skill == .pauses && ex.pauseAt.contains(where: { abs($0 - f) < 0.035 }) { energy = 0; p.voice = 0 }
            p.breath = energy * (seg == nil ? 0.25 : 1)
            return (p, seg, nil)
        }
        guard t.recording || t.playingTake, !t.frames.isEmpty else { return (p, nil, nil) }
        let frames = t.frames
        let i = t.recording ? frames.count - 1 : min(frames.count - 1, max(0, Int(t.playhead * Double(frames.count))))
        let near = frames[max(0, i - 2)...i], peak = max(0.02, frames.map(\.energy).max() ?? 0)
        p.breath = min(1, near.map(\.energy).reduce(0, +) / Double(near.count) / peak)
        let hz = frames[i].pitch, heard = frames.compactMap(\.pitch).sorted()
        if let hz, !heard.isEmpty { p.semis = 12 * log2(hz / heard[heard.count / 2]) }
        p.larynx = VH.larynx(p.semis)
        p.voice = hz != nil && p.breath > 0.1 ? 1 : 0
        if ex.isTone { p.ah(p.breath) } else { p.jaw = 0.2 + 0.3 * p.breath; p.tongue = CGVector(dx: 0, dy: 6 * p.breath); p.gap = 60 * p.breath }
        return (p, nil, hz)
    }

    var caption: String {
        if t.playing { return t.exercise.isTone ? "Example tone · the target shape" : t.technique.usesPitch ? "Example · target: \((t.exampleContrast ? t.exercise.contrastPattern : t.exercise.pattern).cue.lowercased())" : "Example · each sound, roughly timed" }
        if t.recording { return "Your voice · live pitch and loudness" }
        if t.playingTake { return "Your take · pitch and loudness" }
        return "Press Hear target to watch the example, or record to see your own pitch and loudness."
    }

    var tip: String {
        switch t.technique {
        case .pitch, .intonation: return "Higher notes stretch the vocal folds, and the larynx tends to rise a little. Lower notes let it settle."
        case .stress: return "A stressed syllable gets a little more air and a firmer buzz, then the voice relaxes again."
        case .rhythm: return "Beats brighten the air; the small syllables between them stay light and short."
        case .pace: return "Keep the air moving evenly through the whole sentence."
        case .pauses: return "At each divider the buzz stops and the air rests, then the next group starts."
        case .energy: return "More energy means steadier air pressure from the lungs, not shouting."
        case .articulation: return "The buzz comes from the larynx; the jaw, tongue and lips shape it into each sound."
        case .connected: return "In connected speech, the tongue and lips go straight on to the next word."
        }
    }

    func info(_ now: (pose: HeadPose, seg: MouthSeg?, hz: Double?)) -> some View {
        let snd = now.seg.flatMap { MouthSounds.table[$0.sound] }, p = now.pose
        return VStack(alignment: .leading, spacing: 8) {
            Text("VOICE GUIDE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.4).foregroundStyle(VH.teal.opacity(0.85))
            if let snd, let seg = now.seg {
                Text("/\(snd.ipa)/").font(.system(size: 30, weight: .light, design: .rounded)).foregroundStyle(VH.teal).shadow(color: VH.teal.opacity(0.6), radius: 8)
                Text("\(snd.hint), in “\(seg.word)”").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(now.hz.map { "\(Int($0.rounded())) Hz" } ?? "–").font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(VH.teal).shadow(color: VH.teal.opacity(0.6), radius: 8)
                    if let hz = now.hz { Text(VH.note(hz)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(VH.amber) }
                }
            }
            Text(caption).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            meter("buzz", p.voice * (0.3 + 0.7 * p.breath), VH.amber)
            meter("breath", p.breath, VH.teal)
            meter(p.larynx > 0.05 ? "larynx · higher" : p.larynx < -0.05 ? "larynx · lower" : "larynx · middle", 0.5 + p.larynx / 2.4, VH.amber.opacity(0.75))
            Text(tip).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    func meter(_ name: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Color.white.opacity(0.55))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(c).frame(width: g.size.width * min(1, max(0, v)))
                }
            }.frame(height: 4)
        }.accessibilityElement().accessibilityLabel("\(name), \(Int(min(1, max(0, v)) * 100)) percent")
    }
}
