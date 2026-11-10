import UIKit
import WebKit
import CoreMotion
import AVFoundation
import GameController

// MARK: - 空間全体

final class SpaceViewController: UIViewController {
    // 背景
    private let cameraView = UIView()
    private let sceneryView = UIView()
    private let backdrop = CAGradientLayer()
    private let sunLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let starLayer = CAShapeLayer()
    private let theaterDim = CALayer()
    private var stars: [Vec3] = []
    private let startTime = CACurrentMediaTime()

    // 空間と操作
    private let worldView = PassthroughView()
    private let touchView = UIView()
    private let reticle = UIView()
    private let focusDim = UIView()
    private let toastLabel = UILabel()
    private let radar = RadarView(frame: CGRect(x: 0, y: 0, width: 108, height: 108))
    private var launcher: LauncherView?
    private let inputPanel = InputPanel(frame: .zero)
    private weak var inputMonitor: MonitorView?   // アプリ内キーボードの入力先
    private var inputIsURL = false

    // メニュー
    private let menuButton = UIButton(type: .system)
    private let menuPanel = UIStackView()
    private let helpLabel = UILabel()
    private let tabs = UISegmentedControl(items: ["モニター", "空間", "操作"])
    private var pages: [UIStackView] = []
    private var hudButtons: [(button: UIButton, primary: Bool)] = []
    private var themeButton: UIButton?
    private var arButton: UIButton?
    private var lookStickButton: UIButton?
    private var walkStickButton: UIButton?
    private var touchModeButton: UIButton?
    private var radarButton: UIButton?
    private var audioButton: UIButton?
    private var arrangeButton: UIButton?
    private var menuOpen = true

    // スティックと丸いボタン
    private let lookStick = JoystickView(title: "視点")
    private let walkStick = JoystickView(title: "移動")
    private var menuAnchor = FloatAnchor(right: false, bottom: false, dx: 50, dy: 50)
    private var walkAnchor = FloatAnchor(right: false, bottom: true, dx: 84, dy: 96)
    private var lookAnchor = FloatAnchor(right: true, bottom: true, dx: 84, dy: 96)
    private var walkMoved = false
    private var lookMoved = false
    private var stickGrabOffset = CGPoint.zero

    // モニター
    private var monitors: [MonitorView] = []
    private var focused: MonitorView?
    private var grabbed: MonitorView?
    private var gazed: MonitorView?
    private var active: MonitorView?         // 直接操作の設定で、いまタッチに反応するモニター
    private weak var soundOwner: MonitorView? // 最後に見たモニター（音声フォーカスで音を出す1枚）
    private var pinchTarget: MonitorView?
    private let maxMonitors = 8

    // 視点
    private let motion = CMMotionManager()
    private var link: CADisplayLink?
    private var yawOffset = 0.0
    private var pitchOffset = 0.0
    private var dragYaw = 0.0
    private var dragPitch = 0.0
    private var needsRecenter = true
    private var turnRemaining = 0.0          // 「次のモニターへ」などで、これから回す角度
    private var viewMatrix = Mat3.identity
    private var perspective = 500.0
    private var gazeDir = Vec3(0, 0, -1)
    private var camPos = Vec3(0, 0, 0)       // 空間内での自分の位置
    private let walkLimit = 850.0            // 中心から動ける距離

    // 設定
    private var touchMode = 0                // 0: 最大化して操作, 1: 空間で直接（照準の1枚）, 2: 空間で直接（すべて）
    private var directTouch: Bool { touchMode != 0 }
    private var touchOne: Bool { touchMode == 1 }
    private var touchAll: Bool { touchMode == 2 }
    private var audioFocus = false           // true: 見ているモニターだけ音を出す
    private var arrangement = 0
    private let arrangementNames = ["アーチ", "ウォール", "シアター", "コックピット"]
    private let saveKey = "kukan.monitors.v1"
    private let themeKey = "kukan.theme.v1"
    private let touchKey = "kukan.directtouch.v1"
    private let touchModeKey = "kukan.touchmode.v2"
    private let audioKey = "kukan.audiofocus.v1"
    private let radarKey = "kukan.radarhidden.v1"

    // AR・そのほか
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var arOn = false
    private var toastToken = 0
    private var keyboardVisible = false
    private var keyboardTop: CGFloat?        // システムのキーボードの上端（出ていなければ nil）
    private var keyboardNote = "通知なし"
    private var webKeyboardFailed = false    // ページ内の入力欄でキーボードが出なかった
    private var urlKeyboardFailed = false    // URL欄でキーボードが出なかった
    private var focusToken = 0

    /// 拡大縮小・形の変更・移動の対象。照準が乗っているモニター（直接操作の設定では、なければ操作中のモニター）。
    private var currentTarget: MonitorView? {
        gazed ?? (touchOne ? active : nil)
    }

    /// 空間に置かれているモニターが、いまの設定でタッチに反応するか
    private func spacePresentation(for mv: MonitorView) -> MonitorPresentation {
        if touchAll { return .spaceLive }
        if touchOne && active === mv { return .spaceLive }
        return .spaceLocked
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: 画面の組み立て

    override func viewDidLoad() {
        super.viewDidLoad()
        let defaults = UserDefaults.standard
        Palette.index = defaults.integer(forKey: themeKey)
        if defaults.object(forKey: touchModeKey) == nil {
            // 以前の版の設定（オン/オフ）を引き継ぐ
            touchMode = defaults.bool(forKey: touchKey) ? 1 : 0
        } else {
            touchMode = min(2, max(0, defaults.integer(forKey: touchModeKey)))
        }
        audioFocus = defaults.bool(forKey: audioKey)
        view.backgroundColor = .black
        view.layer.insertSublayer(backdrop, at: 0)

        cameraView.isHidden = true
        cameraView.backgroundColor = .black
        view.addSubview(cameraView)

        gridLayer.fillColor = nil
        gridLayer.lineWidth = 1
        theaterDim.backgroundColor = UIColor.black.cgColor
        theaterDim.opacity = 0
        sceneryView.isUserInteractionEnabled = false
        sceneryView.layer.addSublayer(sunLayer)
        sceneryView.layer.addSublayer(gridLayer)
        sceneryView.layer.addSublayer(starLayer)
        sceneryView.layer.addSublayer(theaterDim)
        view.addSubview(sceneryView)

        // 何もない所へのタッチは touchView、モニターへのタッチは上に重ねた worldView が受ける
        view.addSubview(touchView)
        view.addSubview(worldView)
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

        buildMenu()
        view.addSubview(menuPanel)

        // レーダー：点をタップすると、そのモニターの方へ向く
        radar.isHidden = defaults.bool(forKey: radarKey)
        radar.onPick = { [weak self] index in
            guard let self = self, index >= 0, index < self.monitors.count else { return }
            self.turn(to: self.monitors[index])
        }
        view.addSubview(radar)

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

        buildLauncher()

        // アプリ内キーボード
        inputPanel.isHidden = true
        inputPanel.onChange = { [weak self] text in self?.inputChanged(text) }
        inputPanel.onSubmit = { [weak self] text in self?.inputSubmitted(text) }
        inputPanel.onClose = { [weak self] in self?.closeInputPanel() }
        view.addSubview(inputPanel)
        // 外付けキーボードの検出を始めておく（最初の問い合わせでは見つからないことがあるため）
        _ = GCKeyboard.coalesced

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardGone(_:)),
                                               name: UIResponder.keyboardDidHideNotification, object: nil)

        makeStars()
        loadMonitors()
        applyTheme()
        updateSettingTitles()

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
        view.window?.makeKey()
    }

    // MARK: メニュー

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

    /// ボタンの行を縦に積んだ、メニュー1ページ分
    private func makePage(_ rows: [[UIButton]]) -> UIStackView {
        let page = UIStackView()
        page.axis = .vertical
        page.alignment = .center
        page.spacing = 8
        for buttons in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            for b in buttons {
                row.addArrangedSubview(b)
            }
            page.addArrangedSubview(row)
        }
        return page
    }

    private func buildMenu() {
        helpLabel.font = .systemFont(ofSize: 13, weight: .medium)
        helpLabel.textAlignment = .center
        helpLabel.adjustsFontSizeToFitWidth = true
        helpLabel.minimumScaleFactor = 0.6

        tabs.selectedSegmentIndex = 0
        tabs.addTarget(self, action: #selector(tabChanged), for: .valueChanged)

        // 「モニター」のページ
        let arrange = makeHUDButton("並べ方：アーチ", primary: false, action: #selector(nextArrangement))
        arrangeButton = arrange
        let monitorRow1: [UIButton] = [
            makeHUDButton("モニターを追加", primary: true, action: #selector(openLauncher)),
            arrange,
            makeHUDButton("◀ 左のモニターへ", primary: false, action: #selector(lookLeft)),
            makeHUDButton("右のモニターへ ▶", primary: false, action: #selector(lookRight))
        ]
        let monitorRow2: [UIButton] = [
            makeHUDButton("拡大", primary: false, action: #selector(enlargeGazed)),
            makeHUDButton("縮小", primary: false, action: #selector(shrinkGazed)),
            makeHUDButton("形を変える", primary: false, action: #selector(changeGazedShape)),
            makeHUDButton("動画を広げる", primary: false, action: #selector(toggleFillTarget))
        ]

        // 「空間」のページ
        let theme = makeHUDButton("空間：" + Palette.theme.name, primary: false, action: #selector(nextTheme))
        themeButton = theme
        let ar = makeHUDButton("ARに切り替え", primary: false, action: #selector(toggleAR))
        arButton = ar
        let radarB = makeHUDButton("レーダー：表示中", primary: false, action: #selector(toggleRadar))
        radarButton = radarB
        let audio = makeHUDButton("音声フォーカス：オフ", primary: false, action: #selector(toggleAudioFocus))
        audioButton = audio
        let spaceRow1: [UIButton] = [theme, ar, makeHUDButton("視点リセット", primary: false, action: #selector(recenter))]
        let spaceRow2: [UIButton] = [radarB, audio]

        // 「操作」のページ
        let touchB = makeHUDButton("画面操作：最大化", primary: false, action: #selector(toggleTouchMode))
        touchModeButton = touchB
        let walkB = makeHUDButton("移動スティック：表示中", primary: false, action: #selector(toggleWalkStick))
        walkStickButton = walkB
        let lookB = makeHUDButton("視点スティック：表示中", primary: false, action: #selector(toggleLookStick))
        lookStickButton = lookB
        let controlRow1: [UIButton] = [touchB]
        let controlRow2: [UIButton] = [walkB, lookB]

        pages = [
            makePage([monitorRow1, monitorRow2]),
            makePage([spaceRow1, spaceRow2]),
            makePage([controlRow1, controlRow2])
        ]

        menuPanel.axis = .vertical
        menuPanel.alignment = .center
        menuPanel.spacing = 8
        menuPanel.addArrangedSubview(helpLabel)
        menuPanel.addArrangedSubview(tabs)
        for page in pages {
            menuPanel.addArrangedSubview(page)
        }
        showPage(0)
    }

    @objc private func tabChanged() {
        showPage(tabs.selectedSegmentIndex)
    }

    private func showPage(_ index: Int) {
        for (i, page) in pages.enumerated() {
            page.isHidden = i != index
        }
        view.setNeedsLayout()
    }

    @objc private func toggleMenu() {
        menuOpen.toggle()
        menuPanel.isHidden = !menuOpen
        view.setNeedsLayout()
    }

    /// 設定に連動するボタンの文字と、操作の説明を付け直す
    private func updateSettingTitles() {
        let touchTitles = ["画面操作：最大化", "画面操作：直接（照準の1枚）", "画面操作：直接（すべて）"]
        setTitle(touchModeButton, touchTitles[touchMode])
        setTitle(walkStickButton, "移動スティック：" + (walkStick.isHidden ? "非表示" : "表示中"))
        setTitle(lookStickButton, "視点スティック：" + (lookStick.isHidden ? "非表示" : "表示中"))
        setTitle(radarButton, "レーダー：" + (radar.isHidden ? "非表示" : "表示中"))
        setTitle(audioButton, "音声フォーカス：" + (audioFocus ? "オン" : "オフ"))
        setTitle(arrangeButton, "並べ方：" + arrangementNames[arrangement])
        setTitle(arButton, arOn ? "VRに戻す" : "ARに切り替え")
        setTitle(themeButton, "空間：" + Palette.theme.name)
        let helps = [
            "照準をモニターに合わせる ／ どこでもタップ：開く ／ 長押し：移動 ／ ピンチ：大きさ変更",
            "照準を合わせたモニター（色付きの枠）だけタッチ操作できる ／ 枠の外を長押し：移動 ／ 枠の外でピンチ：大きさ変更",
            "どのモニターも直接タッチで操作できる ／ 何もない所を長押し：照準のモニターを移動 ／ 何もない所でピンチ：大きさ変更"
        ]
        helpLabel.text = helps[touchMode]
    }

    // MARK: テーマ

    private func applyTheme() {
        let t = Palette.theme
        backdrop.colors = [t.top.cgColor, t.bottom.cgColor]
        gridLayer.strokeColor = t.grid.cgColor
        starLayer.fillColor = t.star.cgColor
        sunLayer.fillColor = (t.sun ?? UIColor.clear).cgColor
        helpLabel.textColor = t.text
        reticle.layer.borderColor = (gazed == nil ? t.text : t.accent).cgColor
        toastLabel.textColor = t.ink
        toastLabel.backgroundColor = t.panel
        toastLabel.layer.borderColor = t.accent.cgColor
        menuButton.backgroundColor = t.panel.withAlphaComponent(0.85)
        menuButton.tintColor = t.accent
        menuButton.layer.borderColor = t.edge.cgColor
        tabs.backgroundColor = t.panel.withAlphaComponent(0.85)
        tabs.selectedSegmentTintColor = t.accent
        tabs.setTitleTextAttributes([NSAttributedString.Key.foregroundColor: t.ink], for: .normal)
        tabs.setTitleTextAttributes([NSAttributedString.Key.foregroundColor: t.accentInk], for: .selected)
        lookStick.applyTheme()
        walkStick.applyTheme()
        radar.applyTheme()
        launcher?.applyTheme()
        inputPanel.applyTheme()
        for item in hudButtons {
            var config = item.button.configuration
            config?.baseBackgroundColor = item.primary ? t.accent : t.panel
            config?.baseForegroundColor = item.primary ? t.accentInk : t.ink
            item.button.configuration = config
        }
        for mv in monitors {
            mv.applyTheme()
        }
        setTitle(themeButton, "空間：" + t.name)
    }

    @objc private func nextTheme() {
        Palette.index = (Palette.index + 1) % Palette.themes.count
        UserDefaults.standard.set(Palette.index, forKey: themeKey)
        applyTheme()
    }

    // MARK: 設定の切り替え

    @objc private func toggleTouchMode() {
        touchMode = (touchMode + 1) % 3
        UserDefaults.standard.set(touchMode, forKey: touchModeKey)
        view.endEditing(true)
        active = nil
        for mv in monitors where mv !== focused {
            mv.setPresentation(touchAll ? .spaceLive : .spaceLocked)
        }
        if touchOne, let mv = gazed { setActive(mv) }
        refreshHighlights()
        updateSettingTitles()
        let notes = [
            "照準を合わせて画面のどこかをタップすると、手元に大きく開きます。",
            "照準を合わせたモニター（色付きの枠）だけ、直接タッチして操作できます。",
            "照準に関係なく、どのモニターも直接タッチして操作できます。"
        ]
        showToast(notes[touchMode])
    }

    @objc private func toggleWalkStick() {
        walkStick.isHidden.toggle()
        walkStick.reset()
        updateSettingTitles()
    }

    @objc private func toggleLookStick() {
        lookStick.isHidden.toggle()
        lookStick.reset()
        updateSettingTitles()
    }

    @objc private func toggleRadar() {
        radar.isHidden.toggle()
        UserDefaults.standard.set(radar.isHidden, forKey: radarKey)
        updateSettingTitles()
    }

    @objc private func toggleAudioFocus() {
        audioFocus.toggle()
        UserDefaults.standard.set(audioFocus, forKey: audioKey)
        applyAudioFocus()
        updateSettingTitles()
        showToast(audioFocus
                  ? "音声フォーカス：最後に照準を合わせたモニターだけ音が出ます。"
                  : "音声フォーカスを切りました。すべてのモニターの音が出ます。")
    }

    /// 音声フォーカスがオンなら、最後に見たモニター以外の音を消す
    private func applyAudioFocus() {
        let owner = focused ?? soundOwner
        for mv in monitors {
            mv.setMuted(audioFocus && owner != nil && mv !== owner)
        }
    }

    /// 直接操作の設定で、タッチに反応するモニターを切り替える（反応するのは常に1枚だけ）
    private func setActive(_ mv: MonitorView) {
        if active === mv { return }
        if let old = active, old !== focused {
            // 入力中の文字が消えないよう、キーボードは閉じない
            old.setPresentation(.spaceLocked, keepEditing: true)
        }
        active = mv
        if mv !== focused { mv.setPresentation(.spaceLive) }
    }

    /// 枠の色を付け直す：照準が乗っているモニターと、直接操作の対象を目立たせる
    private func refreshHighlights() {
        for mv in monitors where mv !== focused && mv !== grabbed {
            mv.setHighlighted(mv === gazed || (touchOne && mv === active))
        }
    }

    /// 広げた動画を見ている間は、映画館のようにまわりを暗くする
    private func updateTheater() {
        let watching = focused ?? gazed ?? soundOwner
        let dim = watching?.videoFill ?? false
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.6)
        theaterDim.opacity = dim ? 0.6 : 0
        CATransaction.commit()
    }

    // MARK: 丸いボタンとスティックの置き場所

    @objc private func moveMenuButton(_ g: UIPanGestureRecognizer) {
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        menuButton.center = clamped(CGPoint(x: menuButton.center.x + d.x, y: menuButton.center.y + d.y), half: 29)
        menuAnchor = anchor(for: menuButton.center)
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
            if stick === walkStick {
                walkAnchor = anchor(for: stick.center)
                walkMoved = true
            } else {
                lookAnchor = anchor(for: stick.center)
                lookMoved = true
            }
        default:
            stick.alpha = 1
            stick.reset()
        }
    }

    private func point(for a: FloatAnchor) -> CGPoint {
        let b = view.bounds
        let safe = view.safeAreaInsets
        return CGPoint(x: a.right ? b.width - safe.right - a.dx : safe.left + a.dx,
                       y: a.bottom ? b.height - safe.bottom - a.dy : safe.top + a.dy)
    }

    private func anchor(for p: CGPoint) -> FloatAnchor {
        let b = view.bounds
        let safe = view.safeAreaInsets
        let right = p.x > b.midX
        let bottom = p.y > b.midY
        return FloatAnchor(right: right, bottom: bottom,
                           dx: right ? b.width - safe.right - p.x : p.x - safe.left,
                           dy: bottom ? b.height - safe.bottom - p.y : p.y - safe.top)
    }

    /// 画面の外に出ないように位置を丸める
    private func clamped(_ p: CGPoint, half: CGFloat) -> CGPoint {
        let b = view.bounds
        let safe = view.safeAreaInsets
        let minX = safe.left + half + 6, maxX = b.width - safe.right - half - 6
        let minY = safe.top + half + 6, maxY = b.height - safe.bottom - half - 6
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)), y: min(max(p.y, minY), max(minY, maxY)))
    }

    // MARK: キーボード

    @objc private func keyboardChanged(_ n: Notification) {
        guard let value = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let f = value.cgRectValue
        let screenH = view.window?.windowScene?.screen.bounds.height ?? view.bounds.height
        keyboardVisible = f.height > 120 && f.minY < screenH - 120
        keyboardNote = "通知あり y=\(Int(f.minY)) 高さ=\(Int(f.height))"
        keyboardTop = keyboardVisible ? view.convert(f, from: nil).minY : nil
        view.setNeedsLayout()
    }

    @objc private func keyboardGone(_ n: Notification) {
        keyboardVisible = false
        keyboardTop = nil
        view.setNeedsLayout()
    }

    /// いま文字入力を受け取っている部品の種類（原因調査用）
    private func firstResponderName() -> String {
        guard let w = view.window, let r = findFirstResponder(in: w) else { return "なし" }
        return String(describing: type(of: r))
    }

    private func findFirstResponder(in v: UIView) -> UIView? {
        if v.isFirstResponder { return v }
        for sub in v.subviews {
            if let r = findFirstResponder(in: sub) { return r }
        }
        return nil
    }

    /// 入力欄にカーソルが入った。少し待ってもシステムのキーボードが出なければ、アプリ内キーボードを開く。
    private func textFocusBegan(_ mv: MonitorView, isURL: Bool, value: String, secure: Bool) {
        view.window?.makeKey()
        if !inputPanel.isHidden && inputMonitor === mv && inputIsURL == isURL { return }
        if isURL ? urlKeyboardFailed : webKeyboardFailed {
            openInputPanel(mv, isURL: isURL, value: value, secure: secure)
            return
        }
        focusToken += 1
        let token = focusToken
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self.focusToken != token || self.keyboardVisible { return }
            if GCKeyboard.coalesced != nil {
                self.showToast("外付けキーボードが接続中のため、画面のキーボードは出ません。モニター上部のキーボードのボタンで、アプリ内キーボードを開けます。")
                return
            }
            let responder = self.firstResponderName()
            let note = self.keyboardNote
            if isURL {
                self.urlKeyboardFailed = true
            } else {
                self.webKeyboardFailed = true
            }
            self.openInputPanel(mv, isURL: isURL, value: value, secure: secure)
            self.showToast("キーボードが出ないため、アプリ内キーボードを開きました（診断：\(isURL ? "URL欄" : "ページ内")／\(responder)／\(note)）")
        }
    }

    // MARK: アプリ内キーボード

    private func openInputPanel(_ mv: MonitorView, isURL: Bool, value: String, secure: Bool) {
        inputMonitor = mv
        inputIsURL = isURL
        inputPanel.open(title: isURL ? "URL または 検索ワードを入力して「決定」" : "ページの入力欄に入力して「決定」",
                        text: isURL ? "" : value, secure: secure)
        inputPanel.isHidden = false
        view.bringSubviewToFront(inputPanel)
        view.setNeedsLayout()
        // システムのキーボードが使える環境なら、ここで出てくる（出なければ五十音のキーで入力する）
        inputPanel.beginInput()
    }

    private func closeInputPanel() {
        inputPanel.endInput()
        inputPanel.isHidden = true
        inputMonitor = nil
    }

    private func inputChanged(_ text: String) {
        guard let mv = inputMonitor else { return }
        if inputIsURL {
            mv.setURLFieldText(text)
        } else {
            mv.setWebFieldValue(text)
        }
    }

    private func inputSubmitted(_ text: String) {
        if let mv = inputMonitor {
            if inputIsURL {
                mv.submitURLText(text)
            } else {
                mv.setWebFieldValue(text)
                mv.submitWebField()
            }
        }
        closeInputPanel()
    }

    // MARK: モニターの大きさ・形・並べ方

    private func setScale(_ mv: MonitorView, _ value: Double) {
        mv.scale = min(2.0, max(0.5, value))
        mv.place()
    }

    /// モニターの形を次のものに変える（標準 → 横長 → 縦長 → 正方形）
    private func cycleShape(_ mv: MonitorView) {
        mv.shape = (mv.shape + 1) % MonitorView.shapes.count
        if mv !== focused {
            mv.bounds = CGRect(origin: .zero, size: mv.spaceSize)
            mv.place()
        }
        saveMonitors()
        showToast("モニターの形：" + mv.shapeName)
    }

    @objc private func changeGazedShape() {
        guard let mv = currentTarget else {
            showToast("形を変えたいモニターに、中央の照準を合わせてください。")
            return
        }
        cycleShape(mv)
    }

    @objc private func enlargeGazed() { stepScale(1.2) }
    @objc private func shrinkGazed() { stepScale(1 / 1.2) }

    private func stepScale(_ factor: Double) {
        guard let mv = currentTarget else {
            showToast("大きさを変えたいモニターに、中央の照準を合わせてください。")
            return
        }
        setScale(mv, mv.scale * factor)
        saveMonitors()
    }

    @objc private func toggleFillTarget() {
        guard let mv = currentTarget else {
            showToast("動画を広げたいモニターに、中央の照準を合わせてください。")
            return
        }
        mv.toggleVideoFill()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchTarget = focused == nil ? currentTarget : nil
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

    @objc private func nextArrangement() {
        arrangement = (arrangement + 1) % arrangementNames.count
        applyArrangement()
        updateSettingTitles()
        showToast("並べ方：" + arrangementNames[arrangement])
    }

    /// 横一列に等間隔で並べる（角度は度）
    private func spread(_ items: [MonitorView], step: Double, pitch: Double, scale: Double) {
        let deg = Double.pi / 180
        for (i, mv) in items.enumerated() {
            mv.yaw = -(Double(i) - Double(items.count - 1) / 2) * step * deg
            mv.pitch = pitch * deg
            mv.scale = scale
        }
    }

    private func applyArrangement() {
        let list = monitors
        switch arrangement {
        case 1:
            // ウォール：上下2段の壁
            let columns = (list.count + 1) / 2
            spread(Array(list.prefix(columns)), step: 40, pitch: -17, scale: 1)
            spread(Array(list.dropFirst(columns)), step: 40, pitch: 17, scale: 1)
        case 2:
            // シアター：主役を正面に大きく、残りは手前下に小さく
            let main = currentTarget ?? list.first
            var rest: [MonitorView] = []
            for mv in list where mv !== main {
                rest.append(mv)
            }
            if let m = main {
                m.yaw = 0
                m.pitch = -4 * Double.pi / 180
                m.scale = 1.6
            }
            spread(rest, step: 26, pitch: 34, scale: 0.6)
        case 3:
            // コックピット：正面に3枚、手前の計器盤に残り
            spread(Array(list.prefix(3)), step: 44, pitch: -10, scale: 1)
            spread(Array(list.dropFirst(3)), step: 30, pitch: 30, scale: 0.7)
        default:
            // アーチ：正面に弧を描いて並べ、5枚目からは上の段
            spread(Array(list.prefix(4)), step: 42, pitch: 0, scale: 1)
            spread(Array(list.dropFirst(4)), step: 42, pitch: -32, scale: 1)
        }
        let moving = list.filter { $0 !== self.focused }
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseInOut], animations: {
            for mv in moving {
                mv.place()
            }
        }, completion: nil)
        saveMonitors()
    }

    // MARK: レイアウト

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        perspective = 0.6 * Double((b.width * b.height).squareRoot())

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = b
        theaterDim.frame = b
        CATransaction.commit()
        cameraView.frame = b
        previewLayer?.frame = b
        updatePreviewOrientation()
        sceneryView.frame = b
        sunLayer.frame = b
        gridLayer.frame = b
        starLayer.frame = b
        worldView.frame = b
        touchView.frame = b
        focusDim.frame = b
        launcher?.frame = b
        reticle.bounds = CGRect(x: 0, y: 0, width: 26, height: 26)
        reticle.center = CGPoint(x: b.midX, y: b.midY)

        let safe = view.safeAreaInsets
        let fit = menuPanel.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let rowSize = CGSize(width: min(fit.width, b.width - 24), height: fit.height)
        let rowY = b.height - safe.bottom - 16 - rowSize.height
        menuPanel.frame = CGRect(x: (b.width - rowSize.width) / 2, y: rowY, width: rowSize.width, height: rowSize.height)
        // 置き場所は画面端からの距離で決めるので、回転や画面サイズの変化にもついてくる。
        // 動かしていないスティックは、メニューの横に置けるなら下側へ、狭ければメニューの上へ。
        let fitsBeside = menuPanel.isHidden || b.width - rowSize.width >= 2 * 164
        let defaultDY = fitsBeside ? 96 : (b.height - safe.bottom) - (rowY - 80)
        if !walkMoved { walkAnchor.dy = defaultDY }
        if !lookMoved { lookAnchor.dy = defaultDY }
        menuButton.center = clamped(point(for: menuAnchor), half: 29)
        walkStick.center = clamped(point(for: walkAnchor), half: 60)
        lookStick.center = clamped(point(for: lookAnchor), half: 60)
        radar.frame = CGRect(x: b.width - safe.right - 16 - 108, y: safe.top + 16, width: 108, height: 108)
        toastLabel.frame = CGRect(x: max(16, (b.width - 640) / 2), y: safe.top + 16, width: min(640, b.width - 32), height: 72)

        if !inputPanel.isHidden {
            // システムのキーボードが出ているときは、その上に入力欄だけを置く
            inputPanel.setKeysHidden(keyboardVisible)
            let panelW = min(b.width - 24, 860)
            let panelH = inputPanel.preferredHeight(width: panelW)
            let bottom = keyboardTop ?? (b.height - safe.bottom)
            inputPanel.frame = CGRect(x: (b.width - panelW) / 2, y: max(safe.top + 8, bottom - 8 - panelH),
                                      width: panelW, height: panelH)
        }

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

    /// いま向いている方角（左回りが正）
    private func gazeHeading() -> Double {
        atan2(-gazeDir.x, -gazeDir.z)
    }

    /// 自分の位置から見た、モニターの方角
    private func heading(to mv: MonitorView) -> Double {
        let c = direction(yaw: mv.yaw, pitch: mv.pitch) * MonitorView.distance - camPos
        return atan2(-c.x, -c.z)
    }

    private func wrapAngle(_ a: Double) -> Double {
        var x = a
        while x > Double.pi { x -= 2 * Double.pi }
        while x < -Double.pi { x += 2 * Double.pi }
        return x
    }

    /// モニターの方へ、なめらかに向きを変える
    private func turn(to mv: MonitorView) {
        turnRemaining = wrapAngle(heading(to: mv) - gazeHeading())
    }

    @objc private func lookLeft() { stepMonitor(1) }
    @objc private func lookRight() { stepMonitor(-1) }

    /// 左（+1）または右（-1）で、いちばん近いモニターへ向く
    private func stepMonitor(_ sign: Double) {
        if focused != nil { return }
        let here = gazeHeading()
        var best: MonitorView?
        var bestDelta = Double.greatestFiniteMagnitude
        for mv in monitors where mv !== gazed {
            var d = wrapAngle(heading(to: mv) - here) * sign
            if d <= 0.05 { d += 2 * Double.pi }
            if d < bestDelta {
                bestDelta = d
                best = mv
            }
        }
        if let mv = best { turn(to: mv) }
    }

    @objc private func recenter() {
        if motion.deviceMotion != nil {
            needsRecenter = true
        } else {
            dragYaw = 0
            dragPitch = 0
        }
        pitchOffset = 0
        turnRemaining = 0
        camPos = Vec3(0, 0, 0)
    }

    // MARK: 毎フレームの更新

    @objc private func tick() {
        let dt = min(0.05, link.map { $0.targetTimestamp - $0.timestamp } ?? 1.0 / 60.0)

        // 視点スティック：倒した方向へ視点を回す
        let look = lookStick.vector
        if !lookStick.isHidden && focused == nil && (look.x != 0 || look.y != 0) {
            let step = 1.4 * dt
            turnRemaining = 0
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

        // 「左/右のモニターへ」やレーダーで指定された向きへ、少しずつ回す
        if abs(turnRemaining) > 0.0005 {
            let part = turnRemaining * min(1.0, dt * 7)
            if motion.deviceMotion != nil {
                yawOffset += part
            } else {
                dragYaw += part
            }
            turnRemaining -= part
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
                gazed = hit
                reticle.layer.borderColor = (hit == nil ? Palette.mute : Palette.accent).cgColor
                if let h = hit {
                    if touchOne { setActive(h) }
                    soundOwner = h
                    if audioFocus { applyAudioFocus() }
                }
                refreshHighlights()
                updateTheater()
            }
        }
        drawScenery()
        if !radar.isHidden { updateRadar() }
        CATransaction.commit()
    }

    /// レーダーに、まわりのモニターの位置を描く（上が自分の正面）
    private func updateRadar() {
        let flat = (gazeDir.x * gazeDir.x + gazeDir.z * gazeDir.z).squareRoot()
        if flat < 0.01 { return }
        let fx = gazeDir.x / flat
        let fz = gazeDir.z / flat
        var blips: [RadarView.Blip] = []
        for mv in monitors {
            let c = direction(yaw: mv.yaw, pitch: mv.pitch) * MonitorView.distance - camPos
            let forward = c.x * fx + c.z * fz
            let right = c.z * fx - c.x * fz
            var x = right / 1700
            var y = -forward / 1700
            let len = (x * x + y * y).squareRoot()
            if len > 1 {
                x /= len
                y /= len
            }
            let hot = mv === gazed || mv === focused || (touchOne && mv === active)
            blips.append(RadarView.Blip(x: CGFloat(x), y: CGFloat(y), hot: hot))
        }
        radar.update(blips)
    }

    /// 視点から出る線（空間座標）が当たるモニターを返す
    private func monitor(alongRay d: Vec3) -> MonitorView? {
        var best: MonitorView?
        var bestT = Double.greatestFiniteMagnitude
        for mv in monitors where mv !== focused {
            let a = mv.yaw, b = mv.pitch
            let halfW = Double(mv.spaceSize.width) / 2 * mv.scale
            let halfH = Double(mv.spaceSize.height) / 2 * mv.scale
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
        let hw = Double(mv.spaceSize.width) / 2 * mv.scale
        let hh = Double(mv.spaceSize.height) / 2 * mv.scale
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

    // MARK: 背景（床の格子・星・太陽）

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
            sunLayer.path = nil
            return
        }
        let b = view.bounds
        let cx = Double(b.midX), cy = Double(b.midY)
        let P = perspective
        let V = viewMatrix
        let near = -20.0
        let time = CACurrentMediaTime() - startTime
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

        // 太陽（あるテーマだけ）：正面の地平線の少し上
        var sunPath: CGPath?
        if Palette.theme.sun != nil {
            let c = V.apply(direction(yaw: 0, pitch: -0.11) * 3000)
            if c.z < -200 {
                let p = proj(c)
                let radius = CGFloat(P * 520 / (-c.z))
                sunPath = CGPath(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2),
                                 transform: nil)
            }
        }
        sunLayer.path = sunPath

        // 星：空全体がゆっくり回る。ハートのテーマでは、ふわふわと上下にも動く。
        let shape = Palette.theme.starShape
        let spin = Mat3.rotY(time * 0.008)
        let dots = CGMutablePath()
        for (i, sPos) in stars.enumerated() {
            var world = spin.apply(sPos)
            if shape == 2 {
                world.y += sin(time * 0.5 + Double(i)) * 70
            }
            let c = V.apply(world)
            if c.z > -100 { continue }
            let p = proj(c)
            let size = CGFloat(2 + (i % 3))
            switch shape {
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

    // MARK: タッチ操作

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        if focused != nil { return }
        if directTouch {
            // 直接操作の設定では、何もない所のタップはキーボードを閉じるだけ
            view.endEditing(true)
            return
        }
        // 指の位置ではなく、中央の照準が乗っているモニターを開く
        if let mv = gazed { focus(mv) }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        turnRemaining = 0
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
            if let mv = currentTarget {
                grabbed = mv
                gazed = nil
                refreshHighlights()
                mv.setHighlighted(true)
                mv.layer.borderWidth = 6
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        case .ended, .cancelled, .failed:
            if let mv = grabbed {
                mv.layer.borderWidth = 3
                grabbed = nil
                refreshHighlights()
                saveMonitors()
            }
        default:
            break
        }
    }

    @objc private func dimTapped() { unfocus() }

    // MARK: 手元に開く・空間に戻す

    private func focus(_ mv: MonitorView) {
        gazed?.setHighlighted(false)
        gazed = nil
        focused = mv
        soundOwner = mv
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
        mv.setPresentation(.maximized)
        mv.alpha = 0
        UIView.animate(withDuration: 0.2) { mv.alpha = 1 }
        if audioFocus { applyAudioFocus() }
    }

    private func unfocus() {
        guard let mv = focused else { return }
        mv.endEditing(true)
        mv.setPresentation(spacePresentation(for: mv))
        mv.removeFromSuperview()
        focused = nil
        attachToWorld(mv)
        refreshHighlights()
        updateTheater()
        focusDim.isHidden = true
        reticle.isHidden = false
        saveMonitors()
    }

    private func attachToWorld(_ mv: MonitorView) {
        mv.layer.transform = CATransform3DIdentity
        mv.bounds = CGRect(origin: .zero, size: mv.spaceSize)
        mv.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        worldView.addSubview(mv)
        mv.place()
    }

    // MARK: モニターの追加・削除・保存

    private func buildLauncher() {
        var widgetItems: [LauncherView.Item] = []
        for w in WebAssets.widgets {
            widgetItems.append(LauncherView.Item(title: w.name, url: WebAssets.widgetURLString(w.id)))
        }
        let siteItems: [LauncherView.Item] = [
            LauncherView.Item(title: "YouTube", url: "https://www.youtube.com/"),
            LauncherView.Item(title: "Google", url: "https://www.google.com/"),
            LauncherView.Item(title: "Wikipedia", url: "https://ja.wikipedia.org/"),
            LauncherView.Item(title: "Yahoo!ニュース", url: "https://news.yahoo.co.jp/"),
            LauncherView.Item(title: "天気（tenki.jp）", url: "https://tenki.jp/"),
            LauncherView.Item(title: "Googleマップ", url: "https://www.google.com/maps")
        ]
        let panel = LauncherView(sections: [
            (title: "サイト", items: siteItems),
            (title: "ウィジェット（通信なしで動く小さな画面）", items: widgetItems)
        ])
        panel.isHidden = true
        panel.onClose = { [weak self] in
            self?.launcher?.isHidden = true
        }
        panel.onPick = { [weak self] urlString in
            self?.launcher?.isHidden = true
            self?.addMonitor(urlString)
        }
        view.addSubview(panel)
        launcher = panel
    }

    @objc private func openLauncher() {
        if monitors.count >= maxMonitors {
            showToast("モニターは\(maxMonitors)枚までです。不要なものを削除してください。")
            return
        }
        if let panel = launcher {
            panel.isHidden = false
            view.bringSubviewToFront(panel)
        }
    }

    /// 見ている方向に、新しいモニターを置く
    private func addMonitor(_ urlString: String) {
        guard monitors.count < maxMonitors, let url = URL(string: urlString) else { return }
        let spot = spherePoint(alongRay: gazeDir)
        _ = makeMonitor(url: url, yaw: spot.yaw, pitch: spot.pitch)
        saveMonitors()
        if audioFocus { applyAudioFocus() }
        showToast("見ている方向にモニターを追加しました。")
    }

    private func makeMonitor(url: URL, yaw: Double, pitch: Double) -> MonitorView {
        let mv = MonitorView(url: url, yaw: yaw, pitch: pitch)
        mv.applyTheme()
        mv.onClose = { [weak self] in self?.unfocus() }
        mv.onTextFocus = { [weak self, weak mv] isURL, value, secure in
            guard let self = self, let mv = mv else { return }
            self.textFocusBegan(mv, isURL: isURL, value: value, secure: secure)
        }
        mv.onKeyboard = { [weak self, weak mv] in
            guard let self = self, let mv = mv else { return }
            // ページ内に入力欄があればそこへ、なければURL欄へ入力する
            self.openInputPanel(mv, isURL: !mv.hasWebField, value: mv.lastWebValue, secure: mv.lastWebSecure)
        }
        mv.onShape = { [weak self, weak mv] in
            guard let self = self, let mv = mv else { return }
            self.cycleShape(mv)
        }
        mv.onMaximize = { [weak self, weak mv] in
            guard let self = self, let mv = mv, self.focused == nil else { return }
            self.focus(mv)
        }
        mv.onDelete = { [weak self, weak mv] in
            guard let self = self, let mv = mv else { return }
            self.remove(mv)
        }
        mv.onChange = { [weak self] in self?.saveMonitors() }
        mv.onFillChanged = { [weak self] in self?.updateTheater() }
        mv.onFillResult = { [weak self] state in
            if state == "on" {
                self?.showToast("動画をモニターいっぱいに広げました。もう一度押すと戻ります。")
            } else if state == "none" {
                self?.showToast("このページで動画が見つかりませんでした。再生を始めてから、もう一度お試しください。")
            }
        }
        mv.setPresentation(touchAll ? .spaceLive : .spaceLocked)
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
        if active === mv { active = nil }
        if gazed === mv { gazed = nil }
        if inputMonitor === mv { closeInputPanel() }
        mv.endEditing(true)
        mv.web.stopLoading()
        mv.removeFromSuperview()
        monitors.removeAll { $0 === mv }
        updateTheater()
        if audioFocus { applyAudioFocus() }
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
                SavedMonitor(url: "https://www.youtube.com/", yaw: 0, pitch: 0, scale: 1, shape: 0),
                SavedMonitor(url: "https://ja.wikipedia.org/", yaw: -42 * deg, pitch: 0, scale: 1, shape: 0),
                SavedMonitor(url: "https://www.google.com/", yaw: 42 * deg, pitch: 0, scale: 1, shape: 0),
                SavedMonitor(url: WebAssets.widgetURLString("clock"), yaw: 0, pitch: -30 * deg, scale: 0.7, shape: 0)
            ]
        }
        for s in saved.prefix(maxMonitors) {
            if let url = URL(string: s.url) {
                let mv = makeMonitor(url: url, yaw: s.yaw, pitch: s.pitch)
                mv.scale = min(2.0, max(0.5, s.scale ?? 1))
                mv.shape = min(MonitorView.shapes.count - 1, max(0, s.shape ?? 0))
                mv.bounds = CGRect(origin: .zero, size: mv.spaceSize)
                mv.place()
            }
        }
    }

    private func saveMonitors() {
        var list: [SavedMonitor] = []
        for mv in monitors {
            list.append(SavedMonitor(url: mv.currentURLString, yaw: mv.yaw, pitch: mv.pitch, scale: mv.scale, shape: mv.shape))
        }
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
