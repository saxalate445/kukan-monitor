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
    var scale: Double?
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
              accentInk: UIColor(white: 1, alpha: 1))
    ]
    static var index = 0
    static var theme: Theme { themes[index % themes.count] }
    static var panel: UIColor { theme.panel }
    static var edge: UIColor { theme.edge }
    static var ink: UIColor { theme.ink }
    static var mute: UIColor { theme.text }
    static var accent: UIColor { theme.accent }
}

// MARK: - 視点スティック（丸い操作パッド）

final class JoystickView: UIView {
    private let knob = UIView()
    private let caption = UILabel()
    private(set) var vector = CGPoint.zero   // 各軸 -1...1

    init(title: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        layer.borderWidth = 2
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
        backgroundColor = Palette.panel.withAlphaComponent(0.55)
        layer.borderColor = Palette.edge.cgColor
        knob.backgroundColor = Palette.accent
        caption.textColor = Palette.ink
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
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

// MARK: - モニター（ブラウザ1枚）

final class MonitorView: UIView, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate {
    static let spaceSize = CGSize(width: 720, height: 540)
    static let distance: Double = 1100

    var yaw: Double
    var pitch: Double
    var scale: Double = 1
    private var highlighted = false
    private var barButtons: [UIButton] = []
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
        bar.addArrangedSubview(makeButton(symbol: "minus.magnifyingglass", title: nil, action: #selector(zoomOut)))
        bar.addArrangedSubview(makeButton(symbol: "plus.magnifyingglass", title: nil, action: #selector(zoomIn)))

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
        barButtons.removeAll { $0 === delete }
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
        barButtons.append(b)
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
        var t = CATransform3DMakeScale(CGFloat(scale), CGFloat(scale), 1)
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, 0, CGFloat(-MonitorView.distance)))
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
        highlighted = on
        layer.borderColor = (on ? Palette.accent : Palette.edge).cgColor
    }

    func applyTheme() {
        backgroundColor = Palette.panel
        setHighlighted(highlighted)
        for b in barButtons { b.tintColor = Palette.accent }
    }

    /// ページの表示倍率（手元に開いているときのボタン用）
    @objc private func zoomIn() { web.pageZoom = min(3.0, web.pageZoom + 0.15) }
    @objc private func zoomOut() { web.pageZoom = max(0.5, web.pageZoom - 0.15) }

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
    private let backdrop = CAGradientLayer()
    private let helpLabel = UILabel()
    private let buttonRow = UIStackView()
    private let menuButton = UIButton(type: .system)
    private let lookStick = JoystickView(title: "視点")
    private let walkStick = JoystickView(title: "移動")
    private var camPos = Vec3(0, 0, 0)      // 空間内での自分の位置
    private let walkLimit = 850.0           // 中心から動ける距離
    private var hudButtons: [(button: UIButton, primary: Bool)] = []
    private var themeButton: UIButton?
    private var lookStickButton: UIButton?
    private var walkStickButton: UIButton?
    private var menuOpen = true
    private var floatingPlaced = false
    private var pitchOffset = 0.0
    private var pinchTarget: MonitorView?
    private var stickGrabOffset = CGPoint.zero
    private let themeKey = "kukan.theme.v1"
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
        Palette.index = UserDefaults.standard.integer(forKey: themeKey)
        view.backgroundColor = .black
        view.layer.insertSublayer(backdrop, at: 0)

        cameraView.isHidden = true
        cameraView.backgroundColor = .black
        view.addSubview(cameraView)

        gridLayer.fillColor = nil
        gridLayer.lineWidth = 1
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
        touchView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        reticle.isUserInteractionEnabled = false
        reticle.layer.borderWidth = 2
        reticle.layer.cornerRadius = 13
        view.addSubview(reticle)

        helpLabel.text = "動かして見回す ／ タップで開く ／ 長押しでモニター移動 ／ ピンチで大きさ変更"
        helpLabel.font = .systemFont(ofSize: 13, weight: .medium)
        helpLabel.textAlignment = .center
        helpLabel.adjustsFontSizeToFitWidth = true
        helpLabel.minimumScaleFactor = 0.6

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 10
        row1.addArrangedSubview(makeHUDButton("モニターを追加", primary: true, action: #selector(addMonitor)))
        let ar = makeHUDButton("ARに切り替え", primary: false, action: #selector(toggleAR))
        arButton = ar
        row1.addArrangedSubview(ar)
        let theme = makeHUDButton("空間：" + Palette.theme.name, primary: false, action: #selector(nextTheme))
        themeButton = theme
        row1.addArrangedSubview(theme)

        let rowS = UIStackView()
        rowS.axis = .horizontal
        rowS.spacing = 10
        let walkB = makeHUDButton("移動スティック：表示中", primary: false, action: #selector(toggleWalkStick))
        walkStickButton = walkB
        rowS.addArrangedSubview(walkB)
        let lookB = makeHUDButton("視点スティック：表示中", primary: false, action: #selector(toggleLookStick))
        lookStickButton = lookB
        rowS.addArrangedSubview(lookB)

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.spacing = 10
        row2.addArrangedSubview(makeHUDButton("拡大", primary: false, action: #selector(enlargeGazed)))
        row2.addArrangedSubview(makeHUDButton("縮小", primary: false, action: #selector(shrinkGazed)))
        row2.addArrangedSubview(makeHUDButton("視点リセット", primary: false, action: #selector(recenter)))
        row2.addArrangedSubview(makeHUDButton("配置リセット", primary: false, action: #selector(resetLayout)))

        buttonRow.axis = .vertical
        buttonRow.alignment = .center
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(helpLabel)
        buttonRow.addArrangedSubview(row1)
        buttonRow.addArrangedSubview(rowS)
        buttonRow.addArrangedSubview(row2)
        view.addSubview(buttonRow)

        // スティック2つ：左下＝自分の移動、右下＝視点。長押しすると置き場所を動かせる。
        for stick in [walkStick, lookStick] {
            let move = UILongPressGestureRecognizer(target: self, action: #selector(dragStick(_:)))
            move.minimumPressDuration = 0.4
            move.allowableMovement = 8
            stick.addGestureRecognizer(move)
            view.addSubview(stick)
        }

        // 丸いメニューボタン：タップでメニューの表示/非表示、ドラッグで移動。
        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        menuButton.bounds = CGRect(x: 0, y: 0, width: 58, height: 58)
        menuButton.layer.cornerRadius = 29
        menuButton.layer.borderWidth = 2
        menuButton.addTarget(self, action: #selector(toggleMenu), for: .touchUpInside)
        menuButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moveMenuButton(_:))))
        view.addSubview(menuButton)

        toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 0
        toastLabel.layer.cornerRadius = 10
        toastLabel.layer.borderWidth = 1
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
        applyTheme()

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
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        let b = UIButton(configuration: config)
        b.addTarget(self, action: action, for: .touchUpInside)
        hudButtons.append((button: b, primary: primary))
        return b
    }

    private func setTitle(_ button: UIButton?, _ title: String) {
        var config = button?.configuration
        config?.title = title
        button?.configuration = config
    }

    // MARK: テーマ

    private func applyTheme() {
        let t = Palette.theme
        backdrop.colors = [t.top.cgColor, t.bottom.cgColor]
        gridLayer.strokeColor = t.grid.cgColor
        starLayer.fillColor = t.star.cgColor
        helpLabel.textColor = t.text
        reticle.layer.borderColor = (gazed == nil ? t.text : t.accent).cgColor
        toastLabel.textColor = t.ink
        toastLabel.backgroundColor = t.panel
        toastLabel.layer.borderColor = t.accent.cgColor
        menuButton.backgroundColor = t.panel.withAlphaComponent(0.85)
        menuButton.tintColor = t.accent
        menuButton.layer.borderColor = t.edge.cgColor
        lookStick.applyTheme()
        walkStick.applyTheme()
        for item in hudButtons {
            var config = item.button.configuration
            config?.baseBackgroundColor = item.primary ? t.accent : t.panel
            config?.baseForegroundColor = item.primary ? t.accentInk : t.ink
            item.button.configuration = config
        }
        for mv in monitors { mv.applyTheme() }
        setTitle(themeButton, "空間：" + t.name)
    }

    @objc private func nextTheme() {
        Palette.index = (Palette.index + 1) % Palette.themes.count
        UserDefaults.standard.set(Palette.index, forKey: themeKey)
        applyTheme()
    }

    // MARK: 丸いボタンと視点スティック

    @objc private func toggleMenu() {
        menuOpen.toggle()
        buttonRow.isHidden = !menuOpen
    }

    @objc private func toggleWalkStick() {
        walkStick.isHidden.toggle()
        walkStick.reset()
        updateStickTitles()
    }

    @objc private func toggleLookStick() {
        lookStick.isHidden.toggle()
        lookStick.reset()
        updateStickTitles()
    }

    private func updateStickTitles() {
        setTitle(walkStickButton, "移動スティック：" + (walkStick.isHidden ? "非表示" : "表示中"))
        setTitle(lookStickButton, "視点スティック：" + (lookStick.isHidden ? "非表示" : "表示中"))
    }

    @objc private func moveMenuButton(_ g: UIPanGestureRecognizer) {
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        menuButton.center = clamped(CGPoint(x: menuButton.center.x + d.x, y: menuButton.center.y + d.y), half: 29)
    }

    @objc private func dragStick(_ g: UILongPressGestureRecognizer) {
        guard let stick = g.view as? JoystickView else { return }
        let p = g.location(in: view)
        switch g.state {
        case .began:
            stick.reset()
            stickGrabOffset = CGPoint(x: stick.center.x - p.x, y: stick.center.y - p.y)
            stick.alpha = 0.6
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .changed:
            stick.center = clamped(CGPoint(x: p.x + stickGrabOffset.x, y: p.y + stickGrabOffset.y), half: 60)
        default:
            stick.alpha = 1
            stick.reset()
        }
    }

    /// 画面の外に出ないように位置を丸める
    private func clamped(_ p: CGPoint, half: CGFloat) -> CGPoint {
        let b = view.bounds
        let safe = view.safeAreaInsets
        let minX = safe.left + half + 6, maxX = b.width - safe.right - half - 6
        let minY = safe.top + half + 6, maxY = b.height - safe.bottom - half - 6
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)), y: min(max(p.y, minY), max(minY, maxY)))
    }

    // MARK: モニターの大きさ

    private func setScale(_ mv: MonitorView, _ value: Double) {
        mv.scale = min(2.0, max(0.5, value))
        mv.place()
    }

    @objc private func enlargeGazed() { stepScale(1.2) }
    @objc private func shrinkGazed() { stepScale(1 / 1.2) }

    private func stepScale(_ factor: Double) {
        guard let mv = gazed else {
            showToast("大きさを変えたいモニターに、中央の照準を合わせてください。")
            return
        }
        setScale(mv, mv.scale * factor)
        saveMonitors()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchTarget = focused == nil ? (monitor(alongRay: ray(through: g.location(in: view))) ?? gazed) : nil
        case .changed:
            if let mv = pinchTarget {
                setScale(mv, mv.scale * Double(g.scale))
                g.scale = 1
            }
        default:
            if pinchTarget != nil { saveMonitors() }
            pinchTarget = nil
        }
    }

    // MARK: レイアウト

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        perspective = 0.6 * Double((b.width * b.height).squareRoot())

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = b
        CATransaction.commit()
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
        let fit = buttonRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let rowSize = CGSize(width: min(fit.width, b.width - 24), height: fit.height)
        let rowY = b.height - safe.bottom - 16 - rowSize.height
        buttonRow.frame = CGRect(x: (b.width - rowSize.width) / 2, y: rowY, width: rowSize.width, height: rowSize.height)
        if !floatingPlaced && b.width > 0 {
            floatingPlaced = true
            menuButton.center = CGPoint(x: safe.left + 50, y: safe.top + 50)
            // メニューの横に置けるなら親指の届く下側へ、狭ければメニューの上へ
            let fitsBeside = b.width - rowSize.width >= 2 * 164
            let stickY = fitsBeside ? b.height - safe.bottom - 96 : rowY - 80
            walkStick.center = CGPoint(x: safe.left + 84, y: stickY)
            lookStick.center = CGPoint(x: b.width - safe.right - 84, y: stickY)
        }
        menuButton.center = clamped(menuButton.center, half: 29)
        walkStick.center = clamped(walkStick.center, half: 60)
        lookStick.center = clamped(lookStick.center, half: 60)
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
        return Mat3.rotY(yawOffset) * device * Mat3.rotX(pitchOffset)
    }

    private func direction(yaw a: Double, pitch b: Double) -> Vec3 {
        Vec3(-cos(b) * sin(a), sin(b), -cos(b) * cos(a))
    }

    @objc private func tick() {
        let dt = min(0.05, link.map { $0.targetTimestamp - $0.timestamp } ?? 1.0 / 60.0)

        // 視点スティック：倒した方向へ視点を回す
        let look = lookStick.vector
        if !lookStick.isHidden && focused == nil && (look.x != 0 || look.y != 0) {
            let step = 1.4 * dt
            if motion.deviceMotion != nil {
                yawOffset -= Double(look.x) * step
                pitchOffset = max(-1.3, min(1.3, pitchOffset - Double(look.y) * step))
            } else {
                dragYaw -= Double(look.x) * step
                dragPitch = max(-1.4, min(1.4, dragPitch - Double(look.y) * step))
            }
        }

        // 移動スティック：見ている向きを基準に、床の上を前後左右へ動く
        let walk = walkStick.vector
        if !walkStick.isHidden && focused == nil && (walk.x != 0 || walk.y != 0) {
            let flat = (gazeDir.x * gazeDir.x + gazeDir.z * gazeDir.z).squareRoot()
            if flat > 0.01 {
                let f = Vec3(gazeDir.x / flat, 0, gazeDir.z / flat)
                let r = Vec3(-f.z, 0, f.x)
                let step = 700.0 * dt
                var p = camPos + f * (-Double(walk.y) * step) + r * (Double(walk.x) * step)
                let dist = (p.x * p.x + p.z * p.z).squareRoot()
                if dist > walkLimit {
                    p = Vec3(p.x * walkLimit / dist, 0, p.z * walkLimit / dist)
                }
                camPos = p
            }
        }

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
        // 自分の位置のぶんだけ空間をずらしてから回す
        t = CATransform3DConcat(CATransform3DMakeTranslation(CGFloat(-camPos.x), CGFloat(-camPos.y), CGFloat(-camPos.z)), t)
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, 0, CGFloat(perspective)))
        var persp = CATransform3DIdentity
        persp.m34 = CGFloat(-1.0 / perspective)
        t = CATransform3DConcat(t, persp)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        worldView.layer.sublayerTransform = t

        if let g = grabbed {
            let spot = spherePoint(alongRay: gazeDir)
            g.yaw = spot.yaw
            g.pitch = spot.pitch
            g.place()
        }
        for mv in monitors where mv !== focused {
            // 視点の後ろ側に回ったモニターは描かない
            mv.isHidden = !isOnScreen(mv)
        }
        if focused == nil && grabbed == nil {
            let hit = monitor(alongRay: gazeDir)
            if hit !== gazed {
                gazed?.setHighlighted(false)
                hit?.setHighlighted(true)
                gazed = hit
                reticle.layer.borderColor = (hit == nil ? Palette.mute : Palette.accent).cgColor
            }
        }
        drawScenery()
        CATransaction.commit()
    }

    /// 視点から出る線（空間座標）が当たるモニターを返す
    private func monitor(alongRay d: Vec3) -> MonitorView? {
        var best: MonitorView?
        var bestT = Double.greatestFiniteMagnitude
        let baseW = Double(MonitorView.spaceSize.width) / 2
        let baseH = Double(MonitorView.spaceSize.height) / 2
        for mv in monitors where mv !== focused {
            let a = mv.yaw, b = mv.pitch
            let halfW = baseW * mv.scale, halfH = baseH * mv.scale
            let n = direction(yaw: a, pitch: b)
            let k = d.dot(n)
            if k < 0.02 { continue }
            let tt = (MonitorView.distance - camPos.dot(n)) / k
            if tt <= 0 { continue }
            let p = camPos + d * tt - n * MonitorView.distance
            let right = Vec3(cos(a), 0, -sin(a))
            let down = Vec3(sin(b) * sin(a), cos(b), sin(b) * cos(a))
            if abs(p.dot(right)) <= halfW && abs(p.dot(down)) <= halfH && tt < bestT {
                best = mv
                bestT = tt
            }
        }
        return best
    }

    /// 視線が、モニターを並べている球面（中心は空間の原点）に当たる場所
    private func spherePoint(alongRay d: Vec3) -> (yaw: Double, pitch: Double) {
        let D = MonitorView.distance
        let od = camPos.dot(d)
        let disc = od * od - (camPos.dot(camPos) - D * D)
        let t = -od + max(0, disc).squareRoot()
        let q = camPos + d * t
        return (yaw: atan2(-q.x, -q.z), pitch: asin(max(-1, min(1, q.y / D))))
    }

    /// モニターが画面に少しでも映るか。視点の後ろ側だけにある場合は false。
    private func isOnScreen(_ mv: MonitorView) -> Bool {
        let a = mv.yaw, b = mv.pitch
        let n = direction(yaw: a, pitch: b)
        if camPos.dot(n) >= MonitorView.distance { return false }
        let right = Vec3(cos(a), 0, -sin(a))
        let down = Vec3(sin(b) * sin(a), cos(b), sin(b) * cos(a))
        let center = n * MonitorView.distance
        let hw = Double(MonitorView.spaceSize.width) / 2 * mv.scale
        let hh = Double(MonitorView.spaceSize.height) / 2 * mv.scale
        let signs: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        let pts = signs.map { s in
            viewMatrix.apply(center + right * (s.0 * hw) + down * (s.1 * hh) - camPos)
        }
        // 視点より前にある部分だけを切り出す
        let near = -30.0
        var poly: [Vec3] = []
        for i in 0..<4 {
            let p = pts[i], q = pts[(i + 1) % 4]
            let pIn = p.z <= near, qIn = q.z <= near
            if pIn { poly.append(p) }
            if pIn != qIn {
                let t = (near - p.z) / (q.z - p.z)
                poly.append(p + (q - p) * t)
            }
        }
        if poly.isEmpty { return false }
        let bounds = view.bounds
        let cx = Double(bounds.midX), cy = Double(bounds.midY)
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for c in poly {
            let x = cx + perspective * c.x / (-c.z)
            let y = cy + perspective * c.y / (-c.z)
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        let margin = 40.0
        return maxX >= -margin && minX <= Double(bounds.width) + margin
            && maxY >= -margin && minY <= Double(bounds.height) + margin
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
            var a = V.apply(p0 - camPos)
            var c = V.apply(p1 - camPos)
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
            switch Palette.theme.starShape {
            case 1:
                let r = size * 1.6
                dots.move(to: CGPoint(x: p.x, y: p.y - r))
                dots.addLine(to: CGPoint(x: p.x + r * 0.6, y: p.y))
                dots.addLine(to: CGPoint(x: p.x, y: p.y + r))
                dots.addLine(to: CGPoint(x: p.x - r * 0.6, y: p.y))
                dots.closeSubpath()
            case 2:
                let r = size * 2.2
                dots.move(to: CGPoint(x: p.x, y: p.y + r * 0.9))
                dots.addCurve(to: CGPoint(x: p.x - r, y: p.y - r * 0.2),
                              control1: CGPoint(x: p.x - r * 0.6, y: p.y + r * 0.5),
                              control2: CGPoint(x: p.x - r, y: p.y + r * 0.2))
                dots.addArc(center: CGPoint(x: p.x - r * 0.5, y: p.y - r * 0.2), radius: r * 0.5,
                            startAngle: .pi, endAngle: 0, clockwise: false)
                dots.addArc(center: CGPoint(x: p.x + r * 0.5, y: p.y - r * 0.2), radius: r * 0.5,
                            startAngle: .pi, endAngle: 0, clockwise: false)
                dots.addCurve(to: CGPoint(x: p.x, y: p.y + r * 0.9),
                              control1: CGPoint(x: p.x + r, y: p.y + r * 0.2),
                              control2: CGPoint(x: p.x + r * 0.6, y: p.y + r * 0.5))
                dots.closeSubpath()
            default:
                dots.addEllipse(in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
            }
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
        lookStick.reset()
        walkStick.reset()
        view.bringSubviewToFront(focusDim)
        view.addSubview(mv)
        // 文字入力を受け取れるよう、このウィンドウを入力先にする
        view.window?.makeKey()
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
        mv.applyTheme()
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
        let spot = spherePoint(alongRay: gazeDir)
        let mv = makeMonitor(url: url, yaw: spot.yaw, pitch: spot.pitch)
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
        pitchOffset = 0
        camPos = Vec3(0, 0, 0)
    }

    @objc private func resetLayout() {
        let deg = Double.pi / 180
        let lower = Array(monitors.prefix(4))
        let upper = Array(monitors.dropFirst(4))
        for (i, mv) in lower.enumerated() {
            mv.yaw = (Double(i) - Double(lower.count - 1) / 2) * 42 * deg * -1
            mv.pitch = 0
            mv.scale = 1
        }
        for (i, mv) in upper.enumerated() {
            mv.yaw = (Double(i) - Double(upper.count - 1) / 2) * 42 * deg * -1
            mv.pitch = -32 * deg
            mv.scale = 1
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
                SavedMonitor(url: "https://www.youtube.com/", yaw: 0, pitch: 0, scale: 1),
                SavedMonitor(url: "https://ja.wikipedia.org/", yaw: -42 * deg, pitch: 0, scale: 1),
                SavedMonitor(url: "https://www.google.com/", yaw: 42 * deg, pitch: 0, scale: 1)
            ]
        }
        for s in saved.prefix(maxMonitors) {
            if let url = URL(string: s.url) {
                let mv = makeMonitor(url: url, yaw: s.yaw, pitch: s.pitch)
                mv.scale = min(2.0, max(0.5, s.scale ?? 1))
                mv.place()
            }
        }
    }

    private func saveMonitors() {
        let list = monitors.map { SavedMonitor(url: $0.currentURLString, yaw: $0.yaw, pitch: $0.pitch, scale: $0.scale) }
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
        backdrop.isHidden = arOn
        setTitle(arButton, arOn ? "VRに戻す" : "ARに切り替え")
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
