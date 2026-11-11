import UIKit
import SceneKit

// MARK: - 家具（空間のデザイン）
//
// 家具は SceneKit（Apple純正の3D描画）で描く。モニター（ブラウザ）は従来どおり UIKit で手前に重ねる。
// 座標：x=右、z=手前は空間と同じ。SceneKit は y が上向きなので、空間の y（下向き）とは符号が逆。
// 目の高さが原点で、床は 700 下（SceneKit では y = -700）。家具の寸法は「1m = 580」で作る。

/// 保存用の家具1つ分
struct SavedFurniture: Codable {
    var kind: String
    var x: Double
    var z: Double
    var rotation: Double
    var scale: Double
    var color: Int
}

/// 空間に置いた家具1つ
final class FurnitureItem {
    let kind: String
    let node: SCNNode
    var x: Double
    var z: Double
    var rotation: Double      // 上から見た向き（ラジアン）。0 で正面（奥）を向く
    var scale: Double
    var color: Int

    init(kind: String, node: SCNNode, x: Double, z: Double, rotation: Double, scale: Double, color: Int) {
        self.kind = kind
        self.node = node
        self.x = x
        self.z = z
        self.rotation = rotation
        self.scale = scale
        self.color = color
    }

    var name: String { FurnitureFactory.name(of: kind) }
}

// MARK: - 家具の形を作る

enum FurnitureFactory {
    static let floorY: Float = -700
    private static let k: CGFloat = 580   // 1m

    static let catalog: [(id: String, name: String)] = [
        (id: "sofa", name: "ソファ"),
        (id: "armchair", name: "1人がけチェア"),
        (id: "table", name: "ローテーブル"),
        (id: "rug", name: "ラグ"),
        (id: "plant", name: "観葉植物"),
        (id: "lamp", name: "フロアランプ"),
        (id: "shelf", name: "本棚"),
        (id: "beanbag", name: "ビーズクッション")
    ]

    /// 「色を変える」で順に切り替わる色
    static let colors: [(name: String, color: UIColor)] = [
        (name: "グレー", color: UIColor(red: 0.55, green: 0.56, blue: 0.60, alpha: 1)),
        (name: "ネイビー", color: UIColor(red: 0.20, green: 0.26, blue: 0.44, alpha: 1)),
        (name: "マスタード", color: UIColor(red: 0.83, green: 0.62, blue: 0.22, alpha: 1)),
        (name: "セージ", color: UIColor(red: 0.52, green: 0.62, blue: 0.50, alpha: 1)),
        (name: "テラコッタ", color: UIColor(red: 0.76, green: 0.43, blue: 0.31, alpha: 1)),
        (name: "ピンク", color: UIColor(red: 0.93, green: 0.62, blue: 0.72, alpha: 1)),
        (name: "アイボリー", color: UIColor(red: 0.92, green: 0.89, blue: 0.82, alpha: 1)),
        (name: "チャコール", color: UIColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1))
    ]

    private static let wood = UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)
    private static let metal = UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)

    static func name(of kind: String) -> String {
        for c in catalog where c.id == kind { return c.name }
        return kind
    }

    /// 家具ごとの最初の色
    static func defaultColor(of kind: String) -> Int {
        switch kind {
        case "sofa": return 0
        case "armchair": return 2
        case "rug": return 6
        case "plant": return 4
        case "lamp": return 6
        case "shelf": return 7
        case "beanbag": return 5
        default: return 0
        }
    }

    static func make(kind: String) -> SCNNode {
        let root = SCNNode()
        root.name = "furniture"
        switch kind {
        case "sofa": buildSofa(root, width: 2.0, seats: 2)
        case "armchair": buildSofa(root, width: 1.0, seats: 1)
        case "table": buildTable(root)
        case "rug": buildRug(root)
        case "plant": buildPlant(root)
        case "lamp": buildLamp(root)
        case "shelf": buildShelf(root)
        default: buildBeanbag(root)
        }
        return root
    }

    /// 名前が "tint" の部品をその色に、"tint2" を少し明るい色に塗る
    static func applyColor(_ node: SCNNode, index: Int) {
        let c = colors[((index % colors.count) + colors.count) % colors.count].color
        let light = blend(c, UIColor.white, 0.45)
        node.enumerateChildNodes { child, _ in
            if child.name == "tint" {
                child.geometry?.firstMaterial?.diffuse.contents = c
            } else if child.name == "tint2" {
                child.geometry?.firstMaterial?.diffuse.contents = light
            }
        }
    }

    static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        _ = a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        _ = b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    // MARK: 部品

    private static func v(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
        SCNVector3(Float(x * k), Float(y * k), Float(z * k))
    }

    private static func material(_ color: UIColor, shine: CGFloat = 0.15) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = UIColor(white: shine, alpha: 1)
        m.shininess = 0.25
        return m
    }

    @discardableResult
    private static func box(_ root: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, chamfer: CGFloat = 0,
                            color: UIColor, name: String? = nil, at p: SCNVector3) -> SCNNode {
        let g = SCNBox(width: w * k, height: h * k, length: d * k, chamferRadius: chamfer * k)
        g.firstMaterial = material(color)
        let n = SCNNode(geometry: g)
        n.name = name
        n.position = p
        root.addChildNode(n)
        return n
    }

    @discardableResult
    private static func cylinder(_ root: SCNNode, r: CGFloat, h: CGFloat, color: UIColor,
                                 name: String? = nil, at p: SCNVector3) -> SCNNode {
        let g = SCNCylinder(radius: r * k, height: h * k)
        g.radialSegmentCount = 24
        g.firstMaterial = material(color)
        let n = SCNNode(geometry: g)
        n.name = name
        n.position = p
        root.addChildNode(n)
        return n
    }

    @discardableResult
    private static func sphere(_ root: SCNNode, r: CGFloat, color: UIColor, segments: Int = 18,
                               name: String? = nil, at p: SCNVector3) -> SCNNode {
        let g = SCNSphere(radius: r * k)
        g.segmentCount = segments
        g.firstMaterial = material(color)
        let n = SCNNode(geometry: g)
        n.name = name
        n.position = p
        root.addChildNode(n)
        return n
    }

    // MARK: 家具ごとの形（前＝ -z、うしろ＝ +z、床＝ y 0）

    private static func buildSofa(_ root: SCNNode, width: CGFloat, seats: Int) {
        let fabric = colors[0].color
        let half = width / 2
        // 脚
        for x in [-(half - 0.08), half - 0.08] {
            for z in [-0.36, 0.36] as [CGFloat] {
                cylinder(root, r: 0.025, h: 0.06, color: wood, at: v(x, 0.03, z))
            }
        }
        // 台座
        box(root, width, 0.22, 0.86, chamfer: 0.03, color: fabric, name: "tint", at: v(0, 0.17, 0))
        // 背もたれ
        box(root, width, 0.57, 0.2, chamfer: 0.05, color: fabric, name: "tint", at: v(0, 0.565, 0.33))
        // ひじ掛け
        for x in [-(half - 0.09), half - 0.09] {
            box(root, 0.18, 0.58, 0.86, chamfer: 0.06, color: fabric, name: "tint", at: v(x, 0.35, 0))
        }
        // 座面と背中のクッション
        let inner = width - 0.36
        let cushion = inner / CGFloat(seats) - 0.02
        for i in 0 ..< seats {
            let x = -inner / 2 + cushion / 2 + 0.01 + CGFloat(i) * (cushion + 0.02)
            box(root, cushion, 0.14, 0.64, chamfer: 0.05, color: fabric, name: "tint2", at: v(x, 0.35, -0.09))
            box(root, cushion - 0.02, 0.38, 0.14, chamfer: 0.06, color: fabric, name: "tint2", at: v(x, 0.6, 0.16))
        }
    }

    private static func buildTable(_ root: SCNNode) {
        box(root, 1.1, 0.05, 0.6, chamfer: 0.01, color: wood, name: "tint", at: v(0, 0.4, 0))
        for x in [-0.5, 0.5] as [CGFloat] {
            for z in [-0.25, 0.25] as [CGFloat] {
                cylinder(root, r: 0.022, h: 0.375, color: metal, at: v(x, 0.1875, z))
            }
        }
        // 小物：本とマグカップ
        box(root, 0.24, 0.04, 0.17, color: UIColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1), at: v(-0.22, 0.445, 0))
        box(root, 0.22, 0.03, 0.16, color: UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1), at: v(-0.21, 0.48, 0.01))
        cylinder(root, r: 0.04, h: 0.09, color: .white, at: v(0.24, 0.47, 0.05))
    }

    private static func buildRug(_ root: SCNNode) {
        box(root, 2.4, 0.012, 1.7, chamfer: 0.004, color: colors[6].color, name: "tint", at: v(0, 0.006, 0))
        box(root, 2.1, 0.012, 1.4, chamfer: 0.004, color: colors[6].color, name: "tint2", at: v(0, 0.009, 0))
    }

    private static func buildPlant(_ root: SCNNode) {
        cylinder(root, r: 0.17, h: 0.32, color: colors[4].color, name: "tint", at: v(0, 0.16, 0))
        cylinder(root, r: 0.15, h: 0.02, color: UIColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1), at: v(0, 0.32, 0))
        cylinder(root, r: 0.02, h: 0.4, color: UIColor(red: 0.35, green: 0.3, blue: 0.18, alpha: 1), at: v(0, 0.5, 0))
        let greens = [UIColor(red: 0.24, green: 0.50, blue: 0.28, alpha: 1),
                      UIColor(red: 0.32, green: 0.60, blue: 0.33, alpha: 1)]
        let leaves: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0.86, 0, 0.26), (0.16, 0.72, 0.08, 0.18), (-0.15, 0.7, -0.06, 0.19),
            (0.05, 1.0, -0.1, 0.17), (-0.08, 0.62, 0.15, 0.16), (0.12, 0.94, 0.12, 0.14)
        ]
        for (i, l) in leaves.enumerated() {
            sphere(root, r: l.3, color: greens[i % 2], segments: 12, at: v(l.0, l.1, l.2))
        }
    }

    private static func buildLamp(_ root: SCNNode) {
        cylinder(root, r: 0.16, h: 0.03, color: metal, at: v(0, 0.015, 0))
        cylinder(root, r: 0.015, h: 1.4, color: metal, at: v(0, 0.73, 0))
        let shade = SCNCone(topRadius: 0.11 * k, bottomRadius: 0.22 * k, height: 0.3 * k)
        shade.radialSegmentCount = 32
        let m = material(colors[6].color)
        m.isDoubleSided = true
        m.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        m.emission.intensity = 0.55
        shade.firstMaterial = m
        let shadeNode = SCNNode(geometry: shade)
        shadeNode.name = "tint"
        shadeNode.position = v(0, 1.5, 0)
        root.addChildNode(shadeNode)
        let bulb = sphere(root, r: 0.05, color: .white, at: v(0, 1.42, 0))
        bulb.geometry?.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
        // 暖かい色の明かり
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1, green: 0.82, blue: 0.6, alpha: 1)
        light.intensity = 650
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 3.2 * k
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = v(0, 1.42, 0)
        root.addChildNode(lightNode)
    }

    private static func buildShelf(_ root: SCNNode) {
        let c = colors[7].color
        for x in [-0.435, 0.435] as [CGFloat] {
            box(root, 0.03, 1.8, 0.32, color: c, name: "tint", at: v(x, 0.9, 0))
        }
        let levels: [CGFloat] = [0.015, 0.45, 0.9, 1.35, 1.785]
        for y in levels {
            box(root, 0.84, 0.03, 0.32, color: c, name: "tint", at: v(0, y, 0))
        }
        box(root, 0.9, 1.8, 0.01, color: c, name: "tint", at: v(0, 0.9, 0.155))
        // 本（毎回同じ並びになるよう、決まった乱数で作る）
        var seed: UInt64 = 11
        func rnd() -> CGFloat {
            seed = (seed &* 16807) % 2147483647
            return CGFloat(seed) / 2147483647.0
        }
        let bookColors = [UIColor(red: 0.78, green: 0.25, blue: 0.25, alpha: 1), UIColor(red: 0.2, green: 0.35, blue: 0.6, alpha: 1),
                          UIColor(red: 0.9, green: 0.75, blue: 0.3, alpha: 1), UIColor(red: 0.3, green: 0.55, blue: 0.4, alpha: 1),
                          UIColor(red: 0.92, green: 0.9, blue: 0.85, alpha: 1), UIColor(red: 0.45, green: 0.3, blue: 0.55, alpha: 1)]
        for base in levels.prefix(4) {
            var x: CGFloat = -0.4
            while x < 0.36 {
                let w = 0.03 + rnd() * 0.035
                let h = 0.2 + rnd() * 0.12
                if rnd() < 0.85 {
                    box(root, w, h, 0.22, color: bookColors[Int(rnd() * 6) % 6], at: v(x + w / 2, base + 0.015 + h / 2, -0.02))
                }
                x += w + 0.004
            }
        }
    }

    private static func buildBeanbag(_ root: SCNNode) {
        let n = sphere(root, r: 0.42, color: colors[5].color, segments: 28, name: "tint", at: v(0, 0.26, 0))
        n.scale = SCNVector3(1, 0.62, 1)
    }
}

// MARK: - 3Dの空間（家具・床の影・明かり）

@MainActor
final class SpaceScene {
    let view = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let furnitureRoot = SCNNode()
    private let ambient = SCNLight()
    private let sun = SCNLight()
    private let ring = SCNNode()
    private(set) var items: [FurnitureItem] = []
    private let saveKey = "kukan.furniture.v1"

    /// 照準が乗っている家具（足元に輪を出す）
    var hovered: FurnitureItem? {
        didSet { updateRing() }
    }
    /// 長押しで動かしている家具
    var grabbed: FurnitureItem? {
        didSet { updateRing() }
    }

    init() {
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 60
        scene.background.contents = UIColor.clear

        let camera = SCNCamera()
        camera.zNear = 10
        camera.zFar = 40000
        camera.projectionDirection = .vertical
        camera.fieldOfView = 60
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode

        ambient.type = .ambient
        ambient.intensity = 420
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // 斜め上からの光。床に柔らかい影を落とす
        sun.type = .directional
        sun.intensity = 850
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 8
        sun.shadowRadius = 6
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowColor = UIColor(white: 0, alpha: 0.45)
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 6000
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi / 2.6, Float.pi / 6, 0)
        scene.rootNode.addChildNode(sunNode)

        // 影だけを映す、見えない床
        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .shadowOnly
        floor.firstMaterial = floorMaterial
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, FurnitureFactory.floorY, 0)
        scene.rootNode.addChildNode(floorNode)

        scene.rootNode.addChildNode(furnitureRoot)

        // 選んでいる家具の足元に出す輪
        let torus = SCNTorus(ringRadius: 300, pipeRadius: 6)
        let ringMaterial = SCNMaterial()
        ringMaterial.lightingModel = .constant
        ringMaterial.diffuse.contents = UIColor.white
        torus.firstMaterial = ringMaterial
        ring.geometry = torus
        ring.isHidden = true
        scene.rootNode.addChildNode(ring)

        applyTheme()
    }

    // MARK: カメラ

    /// 空間のカメラに合わせる。rotation はカメラ→空間の回転（y上向き）、position は空間の座標（y下向き）。
    func setCamera(rotation r: Mat3, position p: Vec3) {
        let m = SCNMatrix4(
            m11: Float(r.r[0][0]), m12: Float(r.r[1][0]), m13: Float(r.r[2][0]), m14: 0,
            m21: Float(r.r[0][1]), m22: Float(r.r[1][1]), m23: Float(r.r[2][1]), m24: 0,
            m31: Float(r.r[0][2]), m32: Float(r.r[1][2]), m33: Float(r.r[2][2]), m34: 0,
            m41: Float(p.x), m42: Float(-p.y), m43: Float(p.z), m44: 1)
        cameraNode.transform = m
    }

    /// モニターと同じ遠近感（焦点距離 perspective）になるよう、縦の画角を合わせる
    func updateFieldOfView(viewHeight: CGFloat, perspective: Double) {
        guard perspective > 0, viewHeight > 0 else { return }
        let fov = 2 * atan(Double(viewHeight) / 2 / perspective) * 180 / Double.pi
        cameraNode.camera?.fieldOfView = CGFloat(fov)
    }

    func applyTheme() {
        let t = Palette.theme
        ambient.color = FurnitureFactory.blend(t.bottom, UIColor.white, 0.55)
        sun.color = FurnitureFactory.blend(t.top, UIColor.white, 0.8)
        ring.geometry?.firstMaterial?.diffuse.contents = t.accent
    }

    func setDimmed(_ on: Bool) {
        UIView.animate(withDuration: 0.6) {
            self.view.alpha = on ? 0.4 : 1
        }
    }

    // MARK: 家具の出し入れ

    @discardableResult
    func add(kind: String, x: Double, z: Double, rotation: Double, scale: Double, color: Int) -> FurnitureItem {
        let node = FurnitureFactory.make(kind: kind)
        let item = FurnitureItem(kind: kind, node: node, x: x, z: z, rotation: rotation, scale: scale, color: color)
        FurnitureFactory.applyColor(node, index: color)
        furnitureRoot.addChildNode(node)
        items.append(item)
        update(item)
        return item
    }

    func remove(_ item: FurnitureItem) {
        item.node.removeFromParentNode()
        items.removeAll { $0 === item }
        if hovered === item { hovered = nil }
        if grabbed === item { grabbed = nil }
    }

    func removeAll() {
        for item in items {
            item.node.removeFromParentNode()
        }
        items.removeAll()
        hovered = nil
        grabbed = nil
    }

    /// 位置・向き・大きさを3Dの形に反映する
    func update(_ item: FurnitureItem) {
        item.node.position = SCNVector3(Float(item.x), FurnitureFactory.floorY, Float(item.z))
        item.node.eulerAngles = SCNVector3(0, Float(item.rotation), 0)
        let s = Float(item.scale)
        item.node.scale = SCNVector3(s, s, s)
        if item === hovered || item === grabbed { updateRing() }
    }

    func setColor(_ item: FurnitureItem, _ index: Int) {
        item.color = ((index % FurnitureFactory.colors.count) + FurnitureFactory.colors.count) % FurnitureFactory.colors.count
        FurnitureFactory.applyColor(item.node, index: item.color)
    }

    private func updateRing() {
        guard let item = grabbed ?? hovered, let torus = ring.geometry as? SCNTorus else {
            ring.isHidden = true
            return
        }
        let (minB, maxB) = item.node.boundingBox
        let half = max(abs(Double(minB.x)), abs(Double(maxB.x)), abs(Double(minB.z)), abs(Double(maxB.z)))
        torus.ringRadius = CGFloat(max(120, half * item.scale * 1.08))
        torus.pipeRadius = grabbed != nil ? 12 : 6
        ring.position = SCNVector3(Float(item.x), FurnitureFactory.floorY + 4, Float(item.z))
        ring.isHidden = false
    }

    // MARK: 照準

    /// 画面のその位置に見えている家具
    func furniture(at point: CGPoint) -> FurnitureItem? {
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true,
            .rootNode: furnitureRoot
        ]
        guard let hit = view.hitTest(point, options: options).first else { return nil }
        var node: SCNNode? = hit.node
        while let n = node, n.parent !== furnitureRoot {
            node = n.parent
        }
        guard let top = node else { return nil }
        for item in items where item.node === top {
            return item
        }
        return nil
    }

    // MARK: 保存

    func save() {
        var list: [SavedFurniture] = []
        for item in items {
            list.append(SavedFurniture(kind: item.kind, x: item.x, z: item.z, rotation: item.rotation,
                                       scale: item.scale, color: item.color))
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    /// 保存した家具を並べる。保存がまだなければ false
    func load() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let list = try? JSONDecoder().decode([SavedFurniture].self, from: data) else {
            return false
        }
        for f in list.prefix(60) {
            add(kind: f.kind, x: f.x, z: f.z, rotation: f.rotation, scale: min(3, max(0.4, f.scale)), color: f.color)
        }
        return true
    }

    /// おすすめの配置：足元にラグ、うしろにソファ、前にローテーブル、まわりに植物・ランプ・本棚
    func starterLayout() {
        removeAll()
        func face(_ x: Double, _ z: Double) -> Double {
            atan2(x, z)   // 中心（自分）の方を向く
        }
        add(kind: "rug", x: 0, z: -150, rotation: 0, scale: 1, color: 6)
        add(kind: "sofa", x: 0, z: 330, rotation: 0, scale: 1, color: FurnitureFactory.defaultColor(of: "sofa"))
        add(kind: "table", x: 0, z: -620, rotation: 0, scale: 1, color: 0)
        add(kind: "plant", x: -1350, z: -900, rotation: face(-1350, -900), scale: 1.2, color: 4)
        add(kind: "lamp", x: 1250, z: -700, rotation: face(1250, -700), scale: 1, color: 6)
        add(kind: "shelf", x: -1900, z: 250, rotation: face(-1900, 250), scale: 1, color: 7)
        add(kind: "beanbag", x: 1500, z: 300, rotation: face(1500, 300), scale: 1, color: 5)
    }
}
