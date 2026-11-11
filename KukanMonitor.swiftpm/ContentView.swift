import SwiftUI
import UIKit
import WebKit
import CoreMotion

// 空間モニター
// iPadを動かして周囲を見回し、空間に浮かぶ複数のブラウザ画面を操作するアプリ。
// 座標系: x=右, y=下, z=手前（Core Animation と同じ）。視点は原点。

struct ContentView: View {
    var body: some View {
        SpaceView().ignoresSafeArea()
    }
}

struct SpaceView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SpaceViewController {
        SpaceViewController()
    }
    func updateUIViewController(_ uiViewController: SpaceViewController, context: Context) {}
}

// MARK: - 小さな3D計算

struct Vec3 {
    var x: Double
    var y: Double
    var z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    var normalized: Vec3 {
        let l = (x * x + y * y + z * z).squareRoot()
        return l > 0 ? Vec3(x / l, y / l, z / l) : self
    }
    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
}

struct Mat3 {
    var r: [[Double]]   // 行の配列
    static var identity: Mat3 { Mat3(r: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]) }
    static func rotX(_ t: Double) -> Mat3 {
        let c = cos(t), s = sin(t)
        return Mat3(r: [[1, 0, 0], [0, c, -s], [0, s, c]])
    }
    static func rotY(_ t: Double) -> Mat3 {
        let c = cos(t), s = sin(t)
        return Mat3(r: [[c, 0, s], [0, 1, 0], [-s, 0, c]])
    }
    static func * (a: Mat3, b: Mat3) -> Mat3 {
        var out = Mat3.identity
        for i in 0..<3 {
            for j in 0..<3 {
                out.r[i][j] = a.r[i][0] * b.r[0][j] + a.r[i][1] * b.r[1][j] + a.r[i][2] * b.r[2][j]
            }
        }
        return out
    }
    func apply(_ v: Vec3) -> Vec3 {
        Vec3(r[0][0] * v.x + r[0][1] * v.y + r[0][2] * v.z,
             r[1][0] * v.x + r[1][1] * v.y + r[1][2] * v.z,
             r[2][0] * v.x + r[2][1] * v.y + r[2][2] * v.z)
    }
    func applyTransposed(_ v: Vec3) -> Vec3 {
        Vec3(r[0][0] * v.x + r[1][0] * v.y + r[2][0] * v.z,
             r[0][1] * v.x + r[1][1] * v.y + r[2][1] * v.z,
             r[0][2] * v.x + r[1][2] * v.y + r[2][2] * v.z)
    }
}

struct SavedMonitor: Codable {
    var url: String
    var yaw: Double
    var pitch: Double
    var scale: Double?
    var shape: Int?
    var radius: Double?
    var turn: Double?
}

/// 空間の見た目（テーマ）
struct Theme {
    let name: String
    let top: UIColor
    let bottom: UIColor
    let grid: UIColor
    let star: UIColor
    let starShape: Int      // 0=丸, 1=ひし形, 2=ハート
    let panel: UIColor
    let edge: UIColor
    let ink: UIColor
    let text: UIColor
    let accent: UIColor
    let accentInk: UIColor
    var sun: UIColor? = nil  // 地平線に浮かぶ太陽の色（ないテーマは nil）
}

extension UIColor {
    /// CSSで使える #rrggbb 形式
    var cssHex: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        _ = getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}

@MainActor
enum Palette {
    static let themes: [Theme] = [
        Theme(name: "夜空",
              top: UIColor(red: 0.047, green: 0.071, blue: 0.149, alpha: 1),
              bottom: UIColor(red: 0.10, green: 0.14, blue: 0.28, alpha: 1),
              grid: UIColor(red: 0.5, green: 0.61, blue: 0.94, alpha: 0.38),
              star: UIColor(white: 1, alpha: 0.7), starShape: 0,
              panel: UIColor(red: 0.078, green: 0.114, blue: 0.227, alpha: 1),
              edge: UIColor(red: 0.59, green: 0.67, blue: 0.92, alpha: 0.45),
              ink: UIColor(red: 0.91, green: 0.93, blue: 0.98, alpha: 1),
              text: UIColor(red: 0.70, green: 0.75, blue: 0.88, alpha: 1),
              accent: UIColor(red: 1.0, green: 0.706, blue: 0.33, alpha: 1),
              accentInk: UIColor(red: 0.16, green: 0.10, blue: 0.01, alpha: 1)),
        Theme(name: "クール",
              top: UIColor(red: 0.02, green: 0.17, blue: 0.27, alpha: 1),
              bottom: UIColor(red: 0.16, green: 0.62, blue: 0.80, alpha: 1),
              grid: UIColor(red: 0.70, green: 0.97, blue: 1.0, alpha: 0.55),
              star: UIColor(red: 0.80, green: 0.98, blue: 1.0, alpha: 0.85), starShape: 1,
              panel: UIColor(red: 0.03, green: 0.16, blue: 0.24, alpha: 1),
              edge: UIColor(red: 0.55, green: 0.90, blue: 1.0, alpha: 0.55),
              ink: UIColor(red: 0.90, green: 0.98, blue: 1.0, alpha: 1),
              text: UIColor(red: 0.88, green: 0.97, blue: 1.0, alpha: 1),
              accent: UIColor(red: 0.36, green: 0.93, blue: 1.0, alpha: 1),
              accentInk: UIColor(red: 0.01, green: 0.15, blue: 0.20, alpha: 1)),
        Theme(name: "キュート",
              top: UIColor(red: 1.0, green: 0.84, blue: 0.91, alpha: 1),
              bottom: UIColor(red: 1.0, green: 0.62, blue: 0.79, alpha: 1),
              grid: UIColor(white: 1, alpha: 0.7),
              star: UIColor(white: 1, alpha: 0.9), starShape: 2,
              panel: UIColor(red: 0.52, green: 0.15, blue: 0.34, alpha: 1),
              edge: UIColor(white: 1, alpha: 0.8),
              ink: UIColor(red: 1.0, green: 0.94, blue: 0.97, alpha: 1),
              text: UIColor(red: 0.40, green: 0.08, blue: 0.24, alpha: 1),
              accent: UIColor(red: 1.0, green: 0.30, blue: 0.58, alpha: 1),
              accentInk: UIColor(white: 1, alpha: 1)),
        Theme(name: "シンセウェーブ",
              top: UIColor(red: 0.07, green: 0.02, blue: 0.20, alpha: 1),
              bottom: UIColor(red: 0.62, green: 0.16, blue: 0.48, alpha: 1),
              grid: UIColor(red: 1.0, green: 0.36, blue: 0.84, alpha: 0.75),
              star: UIColor(red: 1.0, green: 0.92, blue: 0.70, alpha: 0.85), starShape: 0,
              panel: UIColor(red: 0.12, green: 0.04, blue: 0.24, alpha: 1),
              edge: UIColor(red: 1.0, green: 0.45, blue: 0.88, alpha: 0.6),
              ink: UIColor(red: 1.0, green: 0.95, blue: 1.0, alpha: 1),
              text: UIColor(red: 1.0, green: 0.86, blue: 0.96, alpha: 1),
              accent: UIColor(red: 0.25, green: 0.95, blue: 0.96, alpha: 1),
              accentInk: UIColor(red: 0.03, green: 0.10, blue: 0.16, alpha: 1),
              sun: UIColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 0.95))
    ]
    static var index = 0
    static var theme: Theme { themes[index % themes.count] }
    static var panel: UIColor { theme.panel }
    static var edge: UIColor { theme.edge }
    static var ink: UIColor { theme.ink }
    static var mute: UIColor { theme.text }
    static var accent: UIColor { theme.accent }
}

// MARK: - ガラス（すりガラス風の背景）

/// iPadOSのコントロールセンターのような、背景がぼけて透ける板。
/// 中に部品を置くときは contentView に追加する。
final class GlassView: UIVisualEffectView {
    private let tint = UIView()
    private let highlight = CAGradientLayer()

    init(cornerRadius: CGFloat) {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true
        tint.isUserInteractionEnabled = false
        contentView.addSubview(tint)
        // 上端をほんのり明るくして、ガラスの厚みを出す
        highlight.colors = [UIColor(white: 1, alpha: 0.16).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        highlight.locations = [0, 0.55]
        contentView.layer.addSublayer(highlight)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    func setCornerRadius(_ r: CGFloat) {
        layer.cornerRadius = r
    }

    func applyTheme() {
        tint.backgroundColor = Palette.panel.withAlphaComponent(0.32)
        layer.borderColor = UIColor(white: 1, alpha: 0.24).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tint.frame = contentView.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = contentView.bounds
        CATransaction.commit()
    }
}

// MARK: - 視点スティック（丸い操作パッド）

final class JoystickView: UIView {
    private let glass = GlassView(cornerRadius: 60)
    private let knob = UIView()
    private let caption = UILabel()
    private(set) var vector = CGPoint.zero   // 各軸 -1...1

    init(title: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        glass.isUserInteractionEnabled = false
        addSubview(glass)
        knob.layer.borderWidth = 1
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.35
        knob.layer.shadowRadius = 8
        knob.layer.shadowOffset = CGSize(width: 0, height: 3)
        caption.text = title
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textAlignment = .center
        caption.isUserInteractionEnabled = false
        addSubview(caption)
        knob.isUserInteractionEnabled = false
        knob.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        knob.layer.cornerRadius = 24
        addSubview(knob)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    func applyTheme() {
        glass.applyTheme()
        knob.backgroundColor = Palette.accent.withAlphaComponent(0.9)
        knob.layer.borderColor = UIColor(white: 1, alpha: 0.55).cgColor
        caption.textColor = Palette.ink.withAlphaComponent(0.85)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glass.setCornerRadius(bounds.width / 2)
        caption.frame = CGRect(x: 0, y: 8, width: bounds.width, height: 14)
        if vector == .zero { knob.center = CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    func reset() {
        vector = .zero
        knob.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func update(_ touches: Set<UITouch>) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        var dx = p.x - c.x
        var dy = p.y - c.y
        let maxR = max(1, bounds.width / 2 - 24)
        let len = (dx * dx + dy * dy).squareRoot()
        if len > maxR {
            dx *= maxR / len
            dy *= maxR / len
        }
        knob.center = CGPoint(x: c.x + dx, y: c.y + dy)
        vector = CGPoint(x: dx / maxR, y: dy / maxR)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }
}

/// ページ内の入力欄にカーソルが入ったことを、モニターへ知らせる中継役
@MainActor
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: MonitorView?
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "kukanMedia" {
            owner?.webMediaConflict()
            return
        }
        if message.name == "kukanFill" {
            let on = (message.body as? [String: Any])?["fill"] as? Bool ?? false
            owner?.webFillChanged(on)
            return
        }
        let body = message.body as? [String: Any]
        let value = body?["value"] as? String ?? ""
        let secure = body?["secure"] as? Bool ?? false
        owner?.webFieldFocused(value: value, secure: secure)
    }
}

/// 丸いボタンやスティックの置き場所。近い側の画面端からの距離で覚える。
struct FloatAnchor {
    var right: Bool
    var bottom: Bool
    var dx: CGFloat
    var dy: CGFloat
}

/// モニターの置かれ方
enum MonitorPresentation {
    case spaceLocked   // 空間内・タッチ不可（タップで最大化する設定のとき）
    case spaceLive     // 空間内・そのままタッチ操作できる
    case maximized     // 手元に大きく開いている
}

/// 自分自身ではタッチを受け取らず、中の部品に当たったときだけ反応する入れ物
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
