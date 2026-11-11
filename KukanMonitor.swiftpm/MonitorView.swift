import UIKit
import WebKit

// MARK: - モニター（ブラウザ1枚）

final class MonitorView: UIView, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate {
    /// 選べる形（空間内での幅と高さ）
    static let shapes: [(name: String, size: CGSize)] = [
        (name: "標準", size: CGSize(width: 720, height: 540)),
        (name: "横長", size: CGSize(width: 960, height: 540)),
        (name: "縦長", size: CGSize(width: 480, height: 800)),
        (name: "正方形", size: CGSize(width: 640, height: 640))
    ]
    static let distance: Double = 1100

    var shape = 0
    var spaceSize: CGSize { MonitorView.shapes[shape % MonitorView.shapes.count].size }
    var shapeName: String { MonitorView.shapes[shape % MonitorView.shapes.count].name }

    var yaw: Double
    var pitch: Double
    var scale: Double = 1
    /// 空間の中心からの距離。大画面は遠くに置く
    var radius: Double = MonitorView.distance
    /// その場での向き（上から見た回転）。自分の方を向けるときに使う
    var turn: Double = 0
    /// ほかのモニターと再生を取り合って止められた
    var onMediaConflict: (() -> Void)?

    var onClose: (() -> Void)?
    var onMaximize: (() -> Void)?
    /// 入力欄にカーソルが入った（URL欄かどうか、いまの中身、パスワード欄かどうか）
    var onTextFocus: ((Bool, String, Bool) -> Void)?
    var onKeyboard: (() -> Void)?
    var onDelete: (() -> Void)?
    var onChange: (() -> Void)?
    var onShape: (() -> Void)?
    var onFillChanged: (() -> Void)?
    var onFillResult: ((String) -> Void)?

    let web: WKWebView
    /// 動画をモニターいっぱいに広げているか
    private(set) var videoFill = false
    /// 音声フォーカスで音を消しているか
    private(set) var muted = false
    private(set) var presentation = MonitorPresentation.spaceLocked
    /// ページ内で最後にカーソルが入った入力欄があるか、その中身、パスワード欄かどうか
    private(set) var hasWebField = false
    private(set) var lastWebValue = ""
    private(set) var lastWebSecure = false

    private let homeURL: URL
    private let bar = UIStackView()
    private let field = UITextField()
    private let muteBadge = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))
    private var highlighted = false
    private var lastTouchTime: CFTimeInterval = 0
    private var barButtons: [UIButton] = []
    private var closeButton: UIButton?
    private var maximizeButton: UIButton?
    private var deleteButton: UIButton?
    private var shapeButton: UIButton?

    init(url: URL, yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.homeURL = url
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // 再生の再開をページから行えるよう、再生にタップを必須にしない
        config.mediaTypesRequiringUserActionForPlayback = []
        // ページの全画面は、補助スクリプトでモニター枠の中での全画面に差し替える。
        // iPadの画面全体を乗っ取るネイティブ全画面は使わない。
        config.preferences.isElementFullscreenEnabled = false
        // 補助スクリプト：入力欄の検知、音声フォーカス用の消音、動画を広げる処理
        let focusHandler = WeakScriptHandler()
        config.userContentController.add(focusHandler, name: "kukanFocus")
        config.userContentController.add(focusHandler, name: "kukanFill")
        config.userContentController.add(focusHandler, name: "kukanMedia")
        config.userContentController.addUserScript(
            WKUserScript(source: WebAssets.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        self.web = WKWebView(frame: .zero, configuration: config)
        super.init(frame: CGRect(origin: .zero, size: MonitorView.shapes[0].size))

        focusHandler.owner = self
        backgroundColor = Palette.panel.withAlphaComponent(0.55)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 2
        layer.borderColor = Palette.edge.cgColor
        layer.allowsEdgeAntialiasing = true
        clipsToBounds = true

        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        addSubview(web)

        muteBadge.tintColor = UIColor.white
        muteBadge.backgroundColor = UIColor(white: 0, alpha: 0.6)
        muteBadge.contentMode = .center
        muteBadge.layer.cornerRadius = 18
        muteBadge.clipsToBounds = true
        muteBadge.isHidden = true
        addSubview(muteBadge)

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

        field.borderStyle = .none
        field.backgroundColor = UIColor(white: 0, alpha: 0.3)
        field.textColor = .white
        field.layer.cornerRadius = 10
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        field.leftViewMode = .always
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

        bar.addArrangedSubview(makeButton(symbol: "keyboard", title: nil, action: #selector(keyboardTapped)))
        bar.addArrangedSubview(makeButton(symbol: "play.rectangle.fill", title: nil, action: #selector(fillTapped)))
        let maximize = makeButton(symbol: "arrow.up.left.and.arrow.down.right", title: nil, action: #selector(maximizeTapped))
        bar.addArrangedSubview(maximize)
        maximizeButton = maximize
        let shapeB = makeButton(symbol: "aspectratio", title: nil, action: #selector(shapeTapped))
        bar.addArrangedSubview(shapeB)
        shapeButton = shapeB
        let close = makeButton(symbol: nil, title: "空間に戻す", action: #selector(closeTapped))
        let delete = makeButton(symbol: nil, title: "削除", action: #selector(deleteTapped))
        barButtons.removeAll { $0 === delete }
        delete.tintColor = UIColor.systemRed
        bar.addArrangedSubview(close)
        bar.addArrangedSubview(delete)
        closeButton = close
        deleteButton = delete

        setPresentation(.spaceLocked)
        load(url)
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
        // 上部のバーを隠しているときは、ページを枠いっぱいに広げる
        let top: CGFloat = bar.isHidden ? 0 : 52
        bar.frame = CGRect(x: 14, y: 6, width: max(0, w - 28), height: 40)
        web.frame = CGRect(x: 0, y: top, width: w, height: max(0, h - top))
        muteBadge.frame = CGRect(x: w - 48, y: h - 48, width: 36, height: 36)
    }

    // MARK: 表示するページ

    /// URLを開く。内蔵ウィジェットのアドレスなら、アプリ内のHTMLを表示する。
    func load(_ url: URL) {
        if let id = WebAssets.widgetID(for: url), let html = WebAssets.widgetHTML(id) {
            field.text = WebAssets.widgetName(id) + "（ウィジェット）"
            web.loadHTMLString(html, baseURL: url)
        } else {
            field.text = url.absoluteString
            web.load(URLRequest(url: url))
        }
    }

    /// 内蔵ウィジェットを表示中なら、その種類
    var widgetID: String? {
        WebAssets.widgetID(for: web.url ?? homeURL)
    }

    var currentURLString: String {
        (web.url ?? homeURL).absoluteString
    }

    private func refreshField() {
        if field.isFirstResponder { return }
        if let id = widgetID {
            field.text = WebAssets.widgetName(id) + "（ウィジェット）"
        } else {
            field.text = web.url?.absoluteString
        }
    }

    /// ページへ、いまの状態（消音・ウィジェットの配色）を伝え直す
    private func pushPageState() {
        if muted {
            web.evaluateJavaScript("window.__kukan && window.__kukan.setMuted(true)", completionHandler: nil)
        }
        if widgetID != nil {
            let t = Palette.theme
            let bg = t.panel.cssHex
            let fg = t.ink.cssHex
            let accent = t.accent.cssHex
            let js = "window.__kukan && window.__kukan.setTheme('\(bg)','\(fg)','color-mix(in srgb, \(fg) 62%, \(bg))','\(accent)')"
            web.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: 空間内での配置と見た目

    /// 空間内での位置と向きを反映する
    func place() {
        var t = CATransform3DMakeScale(CGFloat(scale), CGFloat(scale), 1)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(turn), 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, 0, CGFloat(-radius)))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(pitch), 1, 0, 0))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(yaw), 0, 1, 0))
        layer.transform = t
    }

    func setPresentation(_ p: MonitorPresentation, keepEditing: Bool = false) {
        presentation = p
        isUserInteractionEnabled = p != .spaceLocked
        maximizeButton?.isHidden = p != .spaceLive
        shapeButton?.isHidden = p != .spaceLive
        closeButton?.isHidden = p != .maximized
        deleteButton?.isHidden = p != .maximized
        if p == .spaceLocked && !keepEditing { endEditing(true) }
        updateChrome()
    }

    /// 動画を広げている間、空間内では上部のバーを隠して枠全体を動画にする
    private func updateChrome() {
        bar.isHidden = videoFill && presentation != .maximized
        setNeedsLayout()
    }

    func setHighlighted(_ on: Bool) {
        highlighted = on
        layer.borderColor = (on ? Palette.accent : UIColor(white: 1, alpha: 0.3)).cgColor
    }

    func applyTheme() {
        backgroundColor = Palette.panel.withAlphaComponent(0.55)
        setHighlighted(highlighted)
        for b in barButtons { b.tintColor = Palette.accent }
        pushPageState()
    }

    // MARK: 動画を広げる・音を消す

    func toggleVideoFill() {
        setVideoFill(!videoFill)
    }

    /// ページ内の動画を、モニターの枠いっぱいに広げる（または戻す）。
    /// 実際の状態は、ページからの kukanFill メッセージ（webFillChanged）で受け取る。
    func setVideoFill(_ on: Bool) {
        let js = "window.__kukan ? window.__kukan.fill(\(on)) : 'none'"
        web.evaluateJavaScript(js) { [weak self] result, _ in
            self?.onFillResult?((result as? String) ?? "none")
        }
    }

    /// ページの動画が、ほかのモニターとの取り合いで止められた
    func webMediaConflict() {
        onMediaConflict?()
    }

    /// ページ側で全画面にされた／戻された、または fill の結果が確定した
    func webFillChanged(_ on: Bool) {
        if videoFill == on { return }
        videoFill = on
        updateChrome()
        onFillChanged?()
    }

    /// 音声フォーカス用：このモニターの音を消す（または戻す）
    func setMuted(_ on: Bool) {
        if muted == on { return }
        muted = on
        muteBadge.isHidden = !on
        web.evaluateJavaScript("window.__kukan && window.__kukan.setMuted(\(on))", completionHandler: nil)
    }

    /// ページの表示倍率（手元に開いているときのボタン用）
    @objc private func zoomIn() { web.pageZoom = min(3.0, web.pageZoom + 0.15) }
    @objc private func zoomOut() { web.pageZoom = max(0.5, web.pageZoom - 0.15) }

    @objc private func goBack() { web.goBack() }
    @objc private func goForward() { web.goForward() }
    @objc private func reload() {
        // ウィジェットは通信先がないので、アプリ内のHTMLを読み直す
        if let id = widgetID, let url = URL(string: WebAssets.widgetURLString(id)) {
            load(url)
        } else {
            web.reload()
        }
    }
    @objc private func fillTapped() { toggleVideoFill() }
    @objc private func keyboardTapped() { onKeyboard?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func maximizeTapped() { onMaximize?() }
    @objc private func shapeTapped() { onShape?() }
    @objc private func deleteTapped() { onDelete?() }

    // MARK: 文字入力

    /// ページ内の入力欄にカーソルが入った（補助スクリプトからの知らせ）
    func webFieldFocused(value: String, secure: Bool) {
        hasWebField = true
        lastWebValue = value
        lastWebSecure = secure
        // ページが自動でカーソルを入れただけの場合（検索サイトの最初の画面など）は知らせない。
        // 直前にこのモニターを触っていたときだけ、入力を始めたものとして扱う。
        if CACurrentMediaTime() - lastTouchTime < 2.0 {
            onTextFocus?(false, value, secure)
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        onTextFocus?(true, textField.text ?? "", false)
    }

    /// 文字列を、JavaScriptにそのまま書ける形（引用符つき）にする
    private static func jsString(_ text: String) -> String {
        if let data = try? JSONEncoder().encode(text), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\"\""
    }

    /// アプリ内キーボードの文字を、ページ内の入力欄へ入れる
    func setWebFieldValue(_ text: String) {
        lastWebValue = text
        let js = "window.__kukan && window.__kukan.setFieldValue(" + MonitorView.jsString(text) + ")"
        web.evaluateJavaScript(js, completionHandler: nil)
    }

    /// ページ内の入力欄で「決定」（Enter）を押す
    func submitWebField() {
        web.evaluateJavaScript("window.__kukan && window.__kukan.submitField()", completionHandler: nil)
    }

    /// アプリ内キーボードの文字を、上部のURL欄に表示する
    func setURLFieldText(_ text: String) {
        field.text = text
    }

    /// URL欄の文字を確定して開く（URLでなければ検索）
    func submitURLText(_ text: String) {
        field.resignFirstResponder()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = MonitorView.url(from: trimmed) {
            load(url)
        }
    }

    /// タッチされたら、このアプリの画面を文字入力の受け取り先にしておく
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil {
            lastTouchTime = CACurrentMediaTime()
            if let w = window, !w.isKeyWindow { w.makeKey() }
        }
        return hit
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        textField.resignFirstResponder()
        if let url = MonitorView.url(from: text) {
            load(url)
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

    // MARK: ページの読み込み

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshField()
        hasWebField = false
        lastWebValue = ""
        lastWebSecure = false
        // 新しいページは「動画を広げる」が解除された状態から始まる
        if videoFill {
            videoFill = false
            updateChrome()
            onFillChanged?()
        }
        pushPageState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshField()
        pushPageState()
        onChange?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 「戻る」などでウィジェットのアドレスを開こうとした場合は、アプリ内のHTMLを表示し直す
        let failing = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if let url = failing, WebAssets.widgetID(for: url) != nil {
            load(url)
        }
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
