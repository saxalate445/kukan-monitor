import SwiftUI
import UIKit
import WebKit
import CoreMotion
import AVFoundation

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
}

@MainActor
enum Palette {
    static let void = UIColor(red: 0.047, green: 0.071, blue: 0.149, alpha: 1)
    static let panel = UIColor(red: 0.078, green: 0.114, blue: 0.227, alpha: 1)
    static let edge = UIColor(red: 0.59, green: 0.67, blue: 0.92, alpha: 0.45)
    static let ink = UIColor(red: 0.91, green: 0.93, blue: 0.98, alpha: 1)
    static let mute = UIColor(red: 0.58, green: 0.64, blue: 0.78, alpha: 1)
    static let accent = UIColor(red: 1.0, green: 0.706, blue: 0.33, alpha: 1)
}

// MARK: - モニター（ブラウザ1枚）

final class MonitorView: UIView, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate {
    static let spaceSize = CGSize(width: 720, height: 540)
    static let distance: Double = 1100

    var yaw: Double
    var pitch: Double
    var onClose: (() -> Void)?
    var onDelete: (() -> Void)?
    var onChange: (() -> Void)?

    let web: WKWebView
    private let homeURL: URL
    private let bar = UIStackView()
    private let field = UITextField()
    private var closeButton: UIButton?
    private var deleteButton: UIButton?

    init(url: URL, yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.homeURL = url
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        self.web = WKWebView(frame: .zero, configuration: config)
        super.init(frame: CGRect(origin: .zero, size: MonitorView.spaceSize))

        backgroundColor = Palette.panel
        layer.cornerRadius = 14
        layer.borderWidth = 3
        layer.borderColor = Palette.edge.cgColor
        layer.allowsEdgeAntialiasing = true
        clipsToBounds = true

        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        addSubview(web)

        bar.axis = .horizontal
        bar.spacing = 10
        bar.alignment = .center
        bar.overrideUserInterfaceStyle = .dark
        addSubview(bar)

        bar.addArrangedSubview(makeButton(symbol: "chevron.left", title: nil, action: #selector(goBack)))
        bar.addArrangedSubview(makeButton(symbol: "chevron.right", title: nil, action: #selector(goForward)))
        bar.addArrangedSubview(makeButton(symbol: "arrow.clockwise", title: nil, action: #selector(reload)))

        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 15)
        field.placeholder = "URL または 検索ワード"
        field.keyboardType = .webSearch
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        field.delegate = self
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(field)

        let close = makeButton(symbol: nil, title: "空間に戻す", action: #selector(closeTapped))
        let delete = makeButton(symbol: nil, title: "削除", action: #selector(deleteTapped))
        delete.tintColor = UIColor.systemRed
        bar.addArrangedSubview(close)
        bar.addArrangedSubview(delete)
        closeButton = close
        deleteButton = delete

        setFocused(false)
        field.text = url.absoluteString
        web.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    private func makeButton(symbol: String?, title: String?, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        if let symbol = symbol {
            b.setImage(UIImage(systemName: symbol), for: .normal)
        }
        if let title = title {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        }
        b.tintColor = Palette.accent
        b.addTarget(self, action: action, for: .touchUpInside)
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        return b
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        bar.frame = CGRect(x: 14, y: 6, width: max(0, w - 28), height: 40)
        web.frame = CGRect(x: 0, y: 52, width: w, height: max(0, h - 52))
    }

    /// 空間内での位置と向きを反映する
    func place() {
        var t = CATransform3DMakeTranslation(0, 0, CGFloat(-MonitorView.distance))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(pitch), 1, 0, 0))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(yaw), 0, 1, 0))
        layer.transform = t
    }

    func setFocused(_ on: Bool) {
        isUserInteractionEnabled = on
        closeButton?.isHidden = !on
        deleteButton?.isHidden = !on
        if !on { field.resignFirstResponder() }
    }

    func setHighlighted(_ on: Bool) {
        layer.borderColor = (on ? Palette.accent : Palette.edge).cgColor
    }

    var currentURLString: String {
        (web.url ?? homeURL).absoluteString
    }

    @objc private func goBack() { web.goBack() }
    @objc private func goForward() { web.goForward() }
    @objc private func reload() { web.reload() }
    @objc private func closeTapped() { onClose?() }
    @objc private func deleteTapped() { onDelete?() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        textField.resignFirstResponder()
        if let url = MonitorView.url(from: text) {
            web.load(URLRequest(url: url))
        }
        return true
    }

    /// 入力をURLに変換する。URLらしくなければ検索する。
    static func url(from text: String) -> URL? {
        if text.isEmpty { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: text)
        }
        if text.contains(".") && !text.contains(" ") && !text.contains("　") {
            return URL(string: "https://" + text)
        }
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "q", value: text)]
        return comps?.url
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if !field.isFirstResponder { field.text = webView.url?.absoluteString }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !field.isFirstResponder { field.text = webView.url?.absoluteString }
        onChange?()
    }

    // 新しいウィンドウで開くリンクは、同じモニター内で開く
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - 空間全体

final class SpaceViewController: UIViewController {
    private let cameraView = UIView()
    private let sceneryView = UIView()
    private let gridLayer = CAShapeLayer()
    private let starLayer = CAShapeLayer()
    private let worldView = UIView()
    private let touchView = UIView()
    private let reticle = UIView()
    private let helpLabel = UILabel()
    private let buttonRow = UIStackView()
    private let toastLabel = UILabel()
    private let focusDim = UIView()
    private var arButton: UIButton?

    private var monitors: [MonitorView] = []
    private var focused: MonitorView?
    private var grabbed: MonitorView?
    private var gazed: MonitorView?

    private let motion = CMMotionManager()
    private var link: CADisplayLink?
    private var yawOffset = 0.0
    private var dragYaw = 0.0
    private var dragPitch = 0.0
    private var needsRecenter = true
    private var viewMatrix = Mat3.identity
    private var perspective = 500.0
    private var gazeDir = Vec3(0, 0, -1)
    private var stars: [Vec3] = []

    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var arOn = false
    private var toastToken = 0

    private let saveKey = "kukan.monitors.v1"
    private let maxMonitors = 8

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.void

        cameraView.isHidden = true
        cameraView.backgroundColor = .black
        view.addSubview(cameraView)

        gridLayer.fillColor = nil
        gridLayer.strokeColor = UIColor(red: 0.5, green: 0.61, blue: 0.94, alpha: 0.38).cgColor
        gridLayer.lineWidth = 1
        starLayer.fillColor = UIColor(white: 1, alpha: 0.7).cgColor
        sceneryView.isUserInteractionEnabled = false
        sceneryView.layer.addSublayer(gridLayer)
        sceneryView.layer.addSublayer(starLayer)
        view.addSubview(sceneryView)

        worldView.isUserInteractionEnabled = false
        view.addSubview(worldView)

        view.addSubview(touchView)
        touchView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        touchView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.45
        touchView.addGestureRecognizer(hold)

        reticle.isUserInteractionEnabled = false
        reticle.layer.borderWidth = 2
        reticle.layer.borderColor = Palette.ink.cgColor
        reticle.layer.cornerRadius = 13
        view.addSubview(reticle)

        helpLabel.text = "iPadを動かして見回す ／ モニターをタップで手元に開く ／ 長押ししたまま動かすと移動"
        helpLabel.font = .systemFont(ofSize: 13)
        helpLabel.textColor = Palette.mute
        helpLabel.textAlignment = .center
        helpLabel.numberOfLines = 2
        view.addSubview(helpLabel)

        buttonRow.axis = .horizontal
        buttonRow.spacing = 10
        buttonRow.addArrangedSubview(makeHUDButton("モニターを追加", primary: true, action: #selector(addMonitor)))
        let ar = makeHUDButton("ARに切り替え", primary: false, action: #selector(toggleAR))
        arButton = ar
        buttonRow.addArrangedSubview(ar)
        buttonRow.addArrangedSubview(makeHUDButton("正面リセット", primary: false, action: #selector(recenter)))
        buttonRow.addArrangedSubview(makeHUDButton("配置リセット", primary: false, action: #selector(resetLayout)))
        view.addSubview(buttonRow)

        toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = Palette.ink
        toastLabel.backgroundColor = Palette.panel
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 0
        toastLabel.layer.cornerRadius = 10
        toastLabel.layer.borderWidth = 1
        toastLabel.layer.borderColor = Palette.accent.cgColor
        toastLabel.clipsToBounds = true
        toastLabel.isHidden = true
        toastLabel.isUserInteractionEnabled = false
        view.addSubview(toastLabel)

        focusDim.backgroundColor = UIColor(white: 0, alpha: 0.55)
        focusDim.isHidden = true
        focusDim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        view.addSubview(focusDim)

        makeStars()
        loadMonitors()

        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        } else {
            showToast("この端末では動きを取得できません。指でドラッグして見回せます。")
        }

        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func makeHUDButton(_ title: String, primary: Bool, action: Selector) -> UIButton {
        var config = primary ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = title
        config.cornerStyle = .capsule
        config.baseBackgroundColor = primary ? Palette.accent : Palette.panel
        config.baseForegroundColor = primary ? UIColor(red: 0.16, green: 0.1, blue: 0.01, alpha: 1) : Palette.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        let b = UIButton(configuration: config)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: レイアウト

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        perspective = 0.6 * Double((b.width * b.height).squareRoot())

        cameraView.frame = b
        previewLayer?.frame = b
        updatePreviewOrientation()
        sceneryView.frame = b
        gridLayer.frame = b
        starLayer.frame = b
        worldView.frame = b
        touchView.frame = b
        focusDim.frame = b
        reticle.bounds = CGRect(x: 0, y: 0, width: 26, height: 26)
        reticle.center = CGPoint(x: b.midX, y: b.midY)

        let safe = view.safeAreaInsets
        let rowSize = buttonRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let rowY = b.height - safe.bottom - 16 - rowSize.height
        buttonRow.frame = CGRect(x: (b.width - rowSize.width) / 2, y: rowY, width: rowSize.width, height: rowSize.height)
        helpLabel.frame = CGRect(x: 16, y: rowY - 44, width: b.width - 32, height: 36)
        toastLabel.frame = CGRect(x: max(16, (b.width - 520) / 2), y: safe.top + 16, width: min(520, b.width - 32), height: 56)

        let center = CGPoint(x: b.midX, y: b.midY)
        for mv in monitors where mv !== focused {
            mv.center = center
        }
        focused?.frame = focusFrame()
    }

    private func focusFrame() -> CGRect {
        let safe = view.safeAreaInsets
        return view.bounds.inset(by: UIEdgeInsets(top: safe.top + 20, left: safe.left + 20,
                                                  bottom: safe.bottom + 20, right: safe.right + 20))
    }

    // MARK: 視点

    private func currentOrientation() -> UIInterfaceOrientation {
        view.window?.windowScene?.interfaceOrientation ?? .portrait
    }

    /// カメラ（視点）の向き。y上・-z前方の右手系で、カメラ→空間の回転を返す。
    private func cameraRotation() -> Mat3 {
        guard let dm = motion.deviceMotion else {
            return Mat3.rotY(dragYaw) * Mat3.rotX(dragPitch)
        }
        let m = dm.attitude.rotationMatrix
        // 端末の各軸（基準座標系での向き）。基準座標系はZが真上。
        let dx = Vec3(m.m11, m.m12, m.m13)
        let dy = Vec3(m.m21, m.m22, m.m23)
        let dz = Vec3(m.m31, m.m32, m.m33)
        let cx: Vec3
        let cy: Vec3
        switch currentOrientation() {
        case .landscapeRight:
            cx = dy * -1; cy = dx
        case .landscapeLeft:
            cx = dy; cy = dx * -1
        case .portraitUpsideDown:
            cx = dx * -1; cy = dy * -1
        default:
            cx = dx; cy = dy
        }
        // 基準座標系 (X, Y, Z上) → 空間 (x, y上, z) = (X, Z, -Y)
        func w(_ v: Vec3) -> Vec3 { Vec3(v.x, v.z, -v.y) }
        let X = w(cx), Y = w(cy), Z = w(dz)
        let device = Mat3(r: [[X.x, Y.x, Z.x], [X.y, Y.y, Z.y], [X.z, Y.z, Z.z]])
        if needsRecenter {
            yawOffset = -atan2(device.r[0][2], device.r[2][2])
            needsRecenter = false
        }
        return Mat3.rotY(yawOffset) * device
    }

    private func direction(yaw a: Double, pitch b: Double) -> Vec3 {
        Vec3(-cos(b) * sin(a), sin(b), -cos(b) * cos(a))
    }

    @objc private func tick() {
        let R = cameraRotation()
        let s = [1.0, -1.0, 1.0]
        var v = Mat3.identity
        for i in 0..<3 {
            for j in 0..<3 {
                v.r[i][j] = s[i] * s[j] * R.r[j][i]
            }
        }
        viewMatrix = v
        gazeDir = Vec3(-v.r[2][0], -v.r[2][1], -v.r[2][2])

        var t = CATransform3DIdentity
        t.m11 = CGFloat(v.r[0][0]); t.m12 = CGFloat(v.r[1][0]); t.m13 = CGFloat(v.r[2][0])
        t.m21 = CGFloat(v.r[0][1]); t.m22 = CGFloat(v.r[1][1]); t.m23 = CGFloat(v.r[2][1])
        t.m31 = CGFloat(v.r[0][2]); t.m32 = CGFloat(v.r[1][2]); t.m33 = CGFloat(v.r[2][2])
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, 0, CGFloat(perspective)))
        var persp = CATransform3DIdentity
        persp.m34 = CGFloat(-1.0 / perspective)
        t = CATransform3DConcat(t, persp)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        worldView.layer.sublayerTransform = t

        if let g = grabbed {
            g.yaw = atan2(-gazeDir.x, -gazeDir.z)
            g.pitch = asin(max(-1, min(1, gazeDir.y)))
            g.place()
        }
        for mv in monitors where mv !== focused {
            // 視点の後ろ側に回ったモニターは描かない
            mv.isHidden = gazeDir.dot(direction(yaw: mv.yaw, pitch: mv.pitch)) < 0.2
        }
        if focused == nil && grabbed == nil {
            let hit = monitor(alongRay: gazeDir)
            if hit !== gazed {
                gazed?.setHighlighted(false)
                hit?.setHighlighted(true)
                gazed = hit
                reticle.layer.borderColor = (hit == nil ? Palette.ink : Palette.accent).cgColor
            }
        }
        drawScenery()
        CATransaction.commit()
    }

    /// 視点から出る線（空間座標）が当たるモニターを返す
    private func monitor(alongRay d: Vec3) -> MonitorView? {
        var best: MonitorView?
        var bestT = Double.greatestFiniteMagnitude
        let halfW = Double(MonitorView.spaceSize.width) / 2
        let halfH = Double(MonitorView.spaceSize.height) / 2
        for mv in monitors where mv !== focused {
            let a = mv.yaw, b = mv.pitch
            let n = direction(yaw: a, pitch: b)
            let k = d.dot(n)
            if k < 0.05 { continue }
            let tt = MonitorView.distance / k
            let p = d * tt - n * MonitorView.distance
            let right = Vec3(cos(a), 0, -sin(a))
            let down = Vec3(sin(b) * sin(a), cos(b), sin(b) * cos(a))
            if abs(p.dot(right)) <= halfW && abs(p.dot(down)) <= halfH && tt < bestT {
                best = mv
                bestT = tt
            }
        }
        return best
    }

    private func ray(through point: CGPoint) -> Vec3 {
        let b = view.bounds
        let c = Vec3(Double(point.x - b.midX), Double(point.y - b.midY), -perspective).normalized
        return viewMatrix.applyTransposed(c)
    }

    // MARK: 背景（床の格子と星）

    private func makeStars() {
        var seed: UInt64 = 7
        func rnd() -> Double {
            seed = (seed &* 16807) % 2147483647
            return Double(seed) / 2147483647.0
        }
        for _ in 0..<80 {
            let a = rnd() * 2 * Double.pi
            let b = -(0.08 + rnd() * 1.2)
            stars.append(direction(yaw: a, pitch: b) * 3000)
        }
    }

    private func drawScenery() {
        if arOn {
            gridLayer.path = nil
            starLayer.path = nil
            return
        }
        let b = view.bounds
        let cx = Double(b.midX), cy = Double(b.midY)
        let P = perspective
        let V = viewMatrix
        let near = -20.0
        func proj(_ c: Vec3) -> CGPoint {
            CGPoint(x: cx + P * c.x / (-c.z), y: cy + P * c.y / (-c.z))
        }
        let grid = CGMutablePath()
        func line(_ p0: Vec3, _ p1: Vec3) {
            var a = V.apply(p0)
            var c = V.apply(p1)
            if a.z > near && c.z > near { return }
            if a.z > near {
                let t = (near - c.z) / (a.z - c.z)
                a = c + (a - c) * t
            } else if c.z > near {
                let t = (near - a.z) / (c.z - a.z)
                c = a + (c - a) * t
            }
            grid.move(to: proj(a))
            grid.addLine(to: proj(c))
        }
        let floorY = 700.0
        var k = -3000.0
        while k <= 3000.0 {
            line(Vec3(k, floorY, -3000), Vec3(k, floorY, 3000))
            line(Vec3(-3000, floorY, k), Vec3(3000, floorY, k))
            k += 300
        }
        gridLayer.path = grid

        let dots = CGMutablePath()
        for (i, sPos) in stars.enumerated() {
            let c = V.apply(sPos)
            if c.z > -100 { continue }
            let p = proj(c)
            let size = CGFloat(2 + (i % 3))
            dots.addEllipse(in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
        }
        starLayer.path = dots
    }

    // MARK: 操作

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        if focused != nil { return }
        let target = monitor(alongRay: ray(through: g.location(in: view))) ?? gazed
        if let mv = target { focus(mv) }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        if motion.deviceMotion != nil {
            yawOffset += Double(d.x) / perspective
        } else {
            dragYaw += Double(d.x) / perspective
            dragPitch = max(-1.4, min(1.4, dragPitch + Double(d.y) / perspective))
        }
    }

    @objc private func handleHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            if focused != nil { return }
            let target = monitor(alongRay: ray(through: g.location(in: view))) ?? gazed
            if let mv = target {
                grabbed = mv
                gazed?.setHighlighted(false)
                gazed = nil
                mv.setHighlighted(true)
                mv.layer.borderWidth = 6
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        case .ended, .cancelled, .failed:
            if let mv = grabbed {
                mv.layer.borderWidth = 3
                mv.setHighlighted(false)
                grabbed = nil
                saveMonitors()
            }
        default:
            break
        }
    }

    @objc private func dimTapped() { unfocus() }

    private func focus(_ mv: MonitorView) {
        gazed?.setHighlighted(false)
        gazed = nil
        focused = mv
        mv.removeFromSuperview()
        mv.layer.transform = CATransform3DIdentity
        mv.isHidden = false
        mv.setHighlighted(true)
        focusDim.isHidden = false
        reticle.isHidden = true
        view.bringSubviewToFront(focusDim)
        view.addSubview(mv)
        mv.frame = focusFrame()
        mv.setFocused(true)
        mv.alpha = 0
        UIView.animate(withDuration: 0.2) { mv.alpha = 1 }
    }

    private func unfocus() {
        guard let mv = focused else { return }
        mv.endEditing(true)
        mv.setFocused(false)
        mv.setHighlighted(false)
        mv.removeFromSuperview()
        focused = nil
        attachToWorld(mv)
        focusDim.isHidden = true
        reticle.isHidden = false
        saveMonitors()
    }

    private func attachToWorld(_ mv: MonitorView) {
        mv.layer.transform = CATransform3DIdentity
        mv.bounds = CGRect(origin: .zero, size: MonitorView.spaceSize)
        mv.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        worldView.addSubview(mv)
        mv.place()
    }

    // MARK: モニターの追加・削除・保存

    private func makeMonitor(url: URL, yaw: Double, pitch: Double) -> MonitorView {
        let mv = MonitorView(url: url, yaw: yaw, pitch: pitch)
        mv.onClose = { [weak self] in self?.unfocus() }
        mv.onDelete = { [weak self, weak mv] in
            guard let self = self, let mv = mv else { return }
            self.remove(mv)
        }
        mv.onChange = { [weak self] in self?.saveMonitors() }
        monitors.append(mv)
        attachToWorld(mv)
        return mv
    }

    private func remove(_ mv: MonitorView) {
        if focused === mv {
            focused = nil
            focusDim.isHidden = true
            reticle.isHidden = false
        }
        mv.endEditing(true)
        mv.web.stopLoading()
        mv.removeFromSuperview()
        monitors.removeAll { $0 === mv }
        saveMonitors()
    }

    @objc private func addMonitor() {
        if monitors.count >= maxMonitors {
            showToast("モニターは\(maxMonitors)枚までです。不要なものを削除してください。")
            return
        }
        guard let url = URL(string: "https://www.google.com/") else { return }
        let yaw = atan2(-gazeDir.x, -gazeDir.z)
        let pitch = asin(max(-1, min(1, gazeDir.y)))
        let mv = makeMonitor(url: url, yaw: yaw, pitch: pitch)
        saveMonitors()
        focus(mv)
    }

    @objc private func recenter() {
        if motion.deviceMotion != nil {
            needsRecenter = true
        } else {
            dragYaw = 0
            dragPitch = 0
        }
    }

    @objc private func resetLayout() {
        let deg = Double.pi / 180
        let lower = Array(monitors.prefix(4))
        let upper = Array(monitors.dropFirst(4))
        for (i, mv) in lower.enumerated() {
            mv.yaw = (Double(i) - Double(lower.count - 1) / 2) * 42 * deg * -1
            mv.pitch = 0
        }
        for (i, mv) in upper.enumerated() {
            mv.yaw = (Double(i) - Double(upper.count - 1) / 2) * 42 * deg * -1
            mv.pitch = -32 * deg
        }
        for mv in monitors where mv !== focused { mv.place() }
        saveMonitors()
    }

    private func loadMonitors() {
        var saved: [SavedMonitor] = []
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let list = try? JSONDecoder().decode([SavedMonitor].self, from: data) {
            saved = list
        }
        if saved.isEmpty {
            let deg = Double.pi / 180
            saved = [
                SavedMonitor(url: "https://www.youtube.com/", yaw: 0, pitch: 0),
                SavedMonitor(url: "https://ja.wikipedia.org/", yaw: -42 * deg, pitch: 0),
                SavedMonitor(url: "https://www.google.com/", yaw: 42 * deg, pitch: 0)
            ]
        }
        for s in saved.prefix(maxMonitors) {
            if let url = URL(string: s.url) {
                _ = makeMonitor(url: url, yaw: s.yaw, pitch: s.pitch)
            }
        }
    }

    private func saveMonitors() {
        let list = monitors.map { SavedMonitor(url: $0.currentURLString, yaw: $0.yaw, pitch: $0.pitch) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    // MARK: AR（カメラ背景）

    @objc private func toggleAR() {
        if arOn {
            session?.stopRunning()
            cameraView.isHidden = true
            arOn = false
            setARTitle()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil {
            showToast("カメラの設定がありません。アプリ設定の「機能」でカメラを追加してください。")
            return
        }
        Task {
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            if ok {
                self.startCamera()
            } else {
                self.showToast("カメラが許可されていません。設定アプリから許可できます。")
            }
        }
    }

    private func startCamera() {
        if session == nil {
            let s = AVCaptureSession()
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  s.canAddInput(input) else {
                showToast("カメラを起動できませんでした。")
                return
            }
            s.addInput(input)
            let layer = AVCaptureVideoPreviewLayer(session: s)
            layer.videoGravity = .resizeAspectFill
            layer.frame = cameraView.bounds
            cameraView.layer.addSublayer(layer)
            previewLayer = layer
            session = s
        }
        session?.startRunning()
        cameraView.isHidden = false
        arOn = true
        updatePreviewOrientation()
        setARTitle()
    }

    private func setARTitle() {
        var config = arButton?.configuration
        config?.title = arOn ? "VRに戻す" : "ARに切り替え"
        arButton?.configuration = config
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }
        let o = currentOrientation()
        if #available(iOS 17.0, *) {
            let angle: CGFloat
            switch o {
            case .landscapeRight: angle = 0
            case .landscapeLeft: angle = 180
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            switch o {
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait
            }
        }
    }

    // MARK: お知らせ

    private func showToast(_ text: String) {
        toastLabel.text = text
        toastLabel.isHidden = false
        view.bringSubviewToFront(toastLabel)
        toastToken += 1
        let token = toastToken
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self.toastToken == token {
                self.toastLabel.isHidden = true
            }
        }
    }
}
