import UIKit
import UIKit.UIGestureRecognizerSubclass
import SceneKit

// MARK: - ペン（Apple Pencil）
//
// 指は見回しや操作に使い、Apple Pencil で触れたときだけ「書く」。
// ・ホワイトボード：空間に浮かぶ板に書く（モニターの一種として置く）
// ・空中に描く：何もない所をなぞると、その線が3Dの線として空間に残る

/// ペンの色
enum PenPalette {
    static let colors: [(name: String, color: UIColor)] = [
        (name: "青", color: UIColor(red: 0.18, green: 0.50, blue: 1.00, alpha: 1)),
        (name: "黒", color: UIColor(white: 0.10, alpha: 1)),
        (name: "赤", color: UIColor(red: 0.92, green: 0.22, blue: 0.25, alpha: 1)),
        (name: "緑", color: UIColor(red: 0.20, green: 0.70, blue: 0.40, alpha: 1)),
        (name: "黄", color: UIColor(red: 1.00, green: 0.80, blue: 0.15, alpha: 1)),
        (name: "ピンク", color: UIColor(red: 1.00, green: 0.42, blue: 0.70, alpha: 1)),
        (name: "白", color: UIColor(white: 0.97, alpha: 1)),
        (name: "紫", color: UIColor(red: 0.60, green: 0.40, blue: 0.95, alpha: 1))
    ]

    static func index(_ i: Int) -> Int {
        ((i % colors.count) + colors.count) % colors.count
    }

    static func color(_ i: Int) -> UIColor {
        colors[index(i)].color
    }
}

// MARK: - Apple Pencil だけに反応する入力

/// Apple Pencil の線を受け取る。指のタッチは受け取らない（見回しなどの操作はそのまま）。
/// shouldStart が false を返した場所では書かず、下の部品（ボタンやページ）にそのまま渡す。
final class PencilStrokeRecognizer: UIGestureRecognizer {
    var shouldStart: ((CGPoint) -> Bool)?
    private var tracked: UITouch?
    private var pending: [(point: CGPoint, force: CGFloat)] = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = true
    }

    /// 前回から増えた点（位置と筆圧 0〜1）を受け取る
    func takeSamples() -> [(point: CGPoint, force: CGFloat)] {
        let s = pending
        pending = []
        return s
    }

    private func sample(_ t: UITouch) -> (point: CGPoint, force: CGFloat) {
        let f = t.maximumPossibleForce > 0 ? t.force / t.maximumPossibleForce : 0.5
        return (point: t.location(in: view), force: max(0.05, min(1, f)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if tracked != nil {
            for t in touches {
                ignore(t, for: event)
            }
            return
        }
        guard let t = touches.first else { return }
        let p = t.location(in: view)
        if let ok = shouldStart, !ok(p) {
            state = .failed
            return
        }
        tracked = t
        pending.append(sample(t))
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        // 120Hz より細かい点も拾って、なめらかな線にする
        let list = event.coalescedTouches(for: t) ?? [t]
        for c in list {
            pending.append(sample(c))
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        pending.append(sample(t))
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked != nil else { return }
        state = .cancelled
    }

    override func reset() {
        super.reset()
        tracked = nil
        pending = []
    }
}

// MARK: - ホワイトボード

/// ホワイトボードの紙。書いた線はボードごとに、このiPadの中へ保存する。
/// 線の座標は「空間に置いたときの紙の大きさ」を基準にし、手元に開いたときは拡大して表示する。
final class BoardCanvasView: UIView {
    struct Stroke: Codable {
        var color: Int
        var width: Double
        var points: [Double]   // x0, y0, x1, y1, ...
    }

    /// 線を描く面（この座標で書く）
    let content = UIView()
    var logicalSize = CGSize(width: 720, height: 488) {
        didSet { setNeedsLayout() }
    }
    private(set) var strokes: [Stroke] = []
    private var layers: [CAShapeLayer] = []
    private var boardID: String?
    private var current: Stroke?
    private var currentLayer: CAShapeLayer?
    private var baseWidth: CGFloat = 4
    private var forceSum: CGFloat = 0
    private var forceCount: CGFloat = 0

    private static func key(_ id: String) -> String { "kukan.board." + id }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.9, alpha: 1)
        content.backgroundColor = BoardCanvasView.paper()
        content.isUserInteractionEnabled = false
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    /// 方眼の点が入った白い紙
    private static func paper() -> UIColor {
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.985, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.82, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 11, y: 11, width: 2, height: 2))
        }
        return UIColor(patternImage: image)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.transform = .identity
        content.bounds = CGRect(origin: .zero, size: logicalSize)
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let s = min(bounds.width / max(1, logicalSize.width), bounds.height / max(1, logicalSize.height))
        content.transform = CGAffineTransform(scaleX: max(0.01, s), y: max(0.01, s))
    }

    // MARK: 保存

    func load(id: String) {
        boardID = id
        strokes = []
        if let data = UserDefaults.standard.data(forKey: BoardCanvasView.key(id)),
           let list = try? JSONDecoder().decode([Stroke].self, from: data) {
            strokes = list
        }
        rebuildLayers()
    }

    private func save() {
        guard let id = boardID, let data = try? JSONEncoder().encode(strokes) else { return }
        UserDefaults.standard.set(data, forKey: BoardCanvasView.key(id))
    }

    /// ボードを削除したときに、書いた線の保存も消す
    func deleteData() {
        if let id = boardID {
            UserDefaults.standard.removeObject(forKey: BoardCanvasView.key(id))
        }
    }

    // MARK: 書く

    func beginStroke(at p: CGPoint, color: Int, baseWidth: CGFloat, force: CGFloat) {
        self.baseWidth = baseWidth
        forceSum = force
        forceCount = 1
        current = Stroke(color: color, width: Double(widthNow()), points: [Double(p.x), Double(p.y)])
        let layer = makeLayer()
        content.layer.addSublayer(layer)
        currentLayer = layer
        refreshCurrent()
    }

    func addPoint(_ p: CGPoint, force: CGFloat) {
        guard var s = current else { return }
        let n = s.points.count
        if n >= 2 {
            let dx = Double(p.x) - s.points[n - 2]
            let dy = Double(p.y) - s.points[n - 1]
            if dx * dx + dy * dy < 1.5 { return }
        }
        s.points.append(Double(p.x))
        s.points.append(Double(p.y))
        forceSum += force
        forceCount += 1
        s.width = Double(widthNow())
        current = s
    }

    /// まとめて足した点を、画面に反映する
    func refreshCurrent() {
        guard let s = current, let layer = currentLayer else { return }
        style(layer, s)
    }

    /// 線を確定する。確定した線があれば true
    @discardableResult
    func endStroke() -> Bool {
        guard let s = current, let layer = currentLayer else { return false }
        style(layer, s)
        strokes.append(s)
        layers.append(layer)
        current = nil
        currentLayer = nil
        save()
        return true
    }

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        layers.removeLast().removeFromSuperlayer()
        save()
    }

    func clear() {
        strokes.removeAll()
        rebuildLayers()
        save()
    }

    /// 消しゴム：その点の近くを通る線を消す
    @discardableResult
    func erase(near p: CGPoint, radius: CGFloat) -> Bool {
        let r2 = Double(radius * radius)
        var removed = false
        var i = strokes.count - 1
        while i >= 0 {
            let pts = strokes[i].points
            let pad = strokes[i].width / 2
            var hit = false
            var j = 0
            while j + 1 < pts.count {
                let dx = pts[j] - Double(p.x)
                let dy = pts[j + 1] - Double(p.y)
                if dx * dx + dy * dy <= r2 + pad * pad {
                    hit = true
                    break
                }
                j += 2
            }
            if hit {
                strokes.remove(at: i)
                layers.remove(at: i).removeFromSuperlayer()
                removed = true
            }
            i -= 1
        }
        if removed { save() }
        return removed
    }

    // MARK: 描画

    private func widthNow() -> CGFloat {
        let avg = forceCount > 0 ? forceSum / forceCount : 0.5
        return baseWidth * (0.5 + avg * 1.5)
    }

    private func makeLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private func style(_ layer: CAShapeLayer, _ s: Stroke) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.strokeColor = PenPalette.color(s.color).cgColor
        layer.lineWidth = CGFloat(s.width)
        layer.path = BoardCanvasView.path(s.points)
        CATransaction.commit()
    }

    private func rebuildLayers() {
        for l in layers {
            l.removeFromSuperlayer()
        }
        layers = []
        for s in strokes {
            let layer = makeLayer()
            style(layer, s)
            content.layer.addSublayer(layer)
            layers.append(layer)
        }
    }

    /// 点の並びを、なめらかな曲線にする
    private static func path(_ pts: [Double]) -> CGPath {
        let path = CGMutablePath()
        let n = pts.count / 2
        guard n > 0 else { return path }
        let first = CGPoint(x: pts[0], y: pts[1])
        path.move(to: first)
        if n == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            return path
        }
        var prev = first
        for i in 1 ..< n {
            let p = CGPoint(x: pts[i * 2], y: pts[i * 2 + 1])
            let mid = CGPoint(x: (prev.x + p.x) / 2, y: (prev.y + p.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
            prev = p
        }
        path.addLine(to: prev)
        return path
    }
}

// MARK: - 空中の線

/// 空中に描いた線1本。点は空間の座標（y下向き）。
final class AirStroke {
    var points: [Vec3] = []
    var radii: [Double] = []
    let color: Int
    let node = SCNNode()

    init(color: Int) {
        self.color = color
    }
}

struct SavedAirStroke: Codable {
    var color: Int
    var points: [Double]   // x, y, z の順に並べる
    var radii: [Double]
}

/// 線を、丸い断面の管（チューブ）の形にする。光を少し放つ、ネオンのような見た目。
enum AirStrokeGeometry {
    static func make(points: [Vec3], radii: [Double], color: UIColor) -> SCNGeometry {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color
        material.emission.contents = color
        material.emission.intensity = 0.45
        material.isDoubleSided = true

        // SceneKit は y が上向きなので、符号を変える
        let pts = points.map { SIMD3<Float>(Float($0.x), Float(-$0.y), Float($0.z)) }
        if pts.count < 2 {
            let dot = SCNSphere(radius: CGFloat(radii.first ?? 6))
            dot.segmentCount = 12
            dot.firstMaterial = material
            return dot
        }
        let sides = 8
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var idx: [UInt32] = []
        var prevN: SIMD3<Float>?
        var tangents: [SIMD3<Float>] = []
        for i in 0 ..< pts.count {
            let a = pts[max(0, i - 1)]
            let b = pts[min(pts.count - 1, i + 1)]
            var t = b - a
            let tl = simd_length(t)
            t = tl > 1e-5 ? t / tl : SIMD3<Float>(0, 0, 1)
            tangents.append(t)
            // ねじれないよう、前の向きを引き継ぐ
            var n: SIMD3<Float>
            if let pn = prevN {
                n = pn - t * simd_dot(pn, t)
            } else {
                let up: SIMD3<Float> = abs(t.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
                n = simd_cross(t, up)
            }
            if simd_length(n) < 1e-5 {
                n = simd_cross(t, SIMD3<Float>(1, 0, 0))
                if simd_length(n) < 1e-5 { n = SIMD3<Float>(0, 1, 0) }
            }
            n = simd_normalize(n)
            prevN = n
            let bv = simd_cross(t, n)
            let r = Float(radii[min(i, radii.count - 1)])
            for j in 0 ..< sides {
                let ang = Float(j) / Float(sides) * 2 * Float.pi
                let dir = n * cos(ang) + bv * sin(ang)
                verts.append(SCNVector3(pts[i] + dir * r))
                norms.append(SCNVector3(dir))
            }
        }
        let s = UInt32(sides)
        for i in 0 ..< UInt32(pts.count - 1) {
            for j in 0 ..< s {
                let a = i * s + j
                let b = i * s + (j + 1) % s
                let c = (i + 1) * s + j
                let d = (i + 1) * s + (j + 1) % s
                idx += [a, c, b, b, c, d]
            }
        }
        // 両端のふた
        for (ring, sign) in [(0, Float(-1)), (pts.count - 1, Float(1))] {
            let center = UInt32(verts.count)
            verts.append(SCNVector3(pts[ring]))
            norms.append(SCNVector3(tangents[ring] * sign))
            let base = UInt32(ring) * s
            for j in 0 ..< s {
                idx += [center, base + j, base + (j + 1) % s]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
                                   elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        geometry.firstMaterial = material
        return geometry
    }
}

extension SpaceScene {
    private static let airKey = "kukan.air.v1"

    func beginAirStroke(color: Int) -> AirStroke {
        let s = AirStroke(color: color)
        airRoot.addChildNode(s.node)
        airStrokes.append(s)
        return s
    }

    /// 点を足す（近すぎる点は省く）。形の作り直しは refreshAir でまとめて行う
    func addAirPoint(_ s: AirStroke, _ p: Vec3, radius: Double) {
        if let last = s.points.last {
            let d = p - last
            if d.dot(d).squareRoot() < max(2, radius * 0.4) { return }
        }
        if s.points.count >= 3000 { return }
        s.points.append(p)
        s.radii.append(radius)
    }

    func refreshAir(_ s: AirStroke) {
        guard !s.points.isEmpty else { return }
        s.node.geometry = AirStrokeGeometry.make(points: s.points, radii: s.radii, color: PenPalette.color(s.color))
    }

    func removeAirStroke(_ s: AirStroke) {
        s.node.removeFromParentNode()
        airStrokes.removeAll { $0 === s }
    }

    func clearAir() {
        for s in airStrokes {
            s.node.removeFromParentNode()
        }
        airStrokes.removeAll()
    }

    /// 画面のその位置の近くに見えている、空中の線
    func airStroke(nearScreen p: CGPoint, radius: CGFloat) -> AirStroke? {
        let r2 = radius * radius
        for s in airStrokes.reversed() {
            var i = 0
            while i < s.points.count {
                let q = s.points[i]
                let sp = view.projectPoint(SCNVector3(Float(q.x), Float(-q.y), Float(q.z)))
                if sp.z > 0 && sp.z < 1 {
                    let dx = CGFloat(sp.x) - p.x
                    let dy = CGFloat(sp.y) - p.y
                    if dx * dx + dy * dy <= r2 { return s }
                }
                i += 2
            }
        }
        return nil
    }

    func saveAir() {
        var list: [SavedAirStroke] = []
        for s in airStrokes {
            var flat: [Double] = []
            for q in s.points {
                flat += [q.x, q.y, q.z]
            }
            list.append(SavedAirStroke(color: s.color, points: flat, radii: s.radii))
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: SpaceScene.airKey)
        }
    }

    func loadAir() {
        guard let data = UserDefaults.standard.data(forKey: SpaceScene.airKey),
              let list = try? JSONDecoder().decode([SavedAirStroke].self, from: data) else { return }
        for saved in list.prefix(500) {
            let s = beginAirStroke(color: saved.color)
            var i = 0
            while i + 2 < saved.points.count {
                s.points.append(Vec3(saved.points[i], saved.points[i + 1], saved.points[i + 2]))
                i += 3
            }
            s.radii = saved.radii
            while s.radii.count < s.points.count {
                s.radii.append(s.radii.last ?? 8)
            }
            refreshAir(s)
        }
    }
}
