import UIKit

// MARK: - レーダー（周囲のモニターを上から見た小さな地図）

/// ゲームのレーダーと同じ見方：中心が自分、上が自分の正面。
/// 点をタップすると、そのモニターの方へ向きを変える。
final class RadarView: UIView {
    /// 点ひとつ。x・y は -1...1（中心が自分、上が正面）。hot は「いま見ている／操作中」のモニター。
    struct Blip {
        var x: CGFloat
        var y: CGFloat
        var hot: Bool
    }

    var onPick: ((Int) -> Void)?

    private let ring = CAShapeLayer()
    private let dots = CAShapeLayer()
    private let hotDots = CAShapeLayer()
    private let me = CAShapeLayer()
    private var blips: [Blip] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        ring.lineWidth = 2
        layer.addSublayer(ring)
        layer.addSublayer(dots)
        layer.addSublayer(hotDots)
        layer.addSublayer(me)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    func applyTheme() {
        ring.fillColor = Palette.panel.withAlphaComponent(0.6).cgColor
        ring.strokeColor = Palette.edge.cgColor
        dots.fillColor = Palette.ink.withAlphaComponent(0.85).cgColor
        hotDots.fillColor = Palette.accent.cgColor
        me.fillColor = Palette.accent.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        ring.path = CGPath(ellipseIn: b.insetBy(dx: 1, dy: 1), transform: nil)
        // 自分（中心の三角形。とがった側が正面）
        let c = CGPoint(x: b.midX, y: b.midY)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y - 8))
        p.addLine(to: CGPoint(x: c.x + 6, y: c.y + 6))
        p.addLine(to: CGPoint(x: c.x - 6, y: c.y + 6))
        p.closeSubpath()
        me.path = p
    }

    private func position(of b: Blip) -> CGPoint {
        let r = bounds.width / 2 - 12
        return CGPoint(x: bounds.midX + b.x * r, y: bounds.midY + b.y * r)
    }

    func update(_ list: [Blip]) {
        blips = list
        let normal = CGMutablePath()
        let hot = CGMutablePath()
        for b in list {
            let p = position(of: b)
            if b.hot {
                hot.addEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            } else {
                normal.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            }
        }
        dots.path = normal
        hotDots.path = hot
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let touch = g.location(in: self)
        var best = -1
        var bestDistance = CGFloat(34)
        for (i, b) in blips.enumerated() {
            let p = position(of: b)
            let dx = p.x - touch.x
            let dy = p.y - touch.y
            let d = (dx * dx + dy * dy).squareRoot()
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        if best >= 0 { onPick?(best) }
    }
}

// MARK: - モニターを追加するときの一覧

/// よく使うサイトと内蔵ウィジェットを並べた選択パネル
final class LauncherView: UIView {
    struct Item {
        let title: String
        let url: String
    }

    var onPick: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let panel = UIView()
    private let stack = UIStackView()
    private var items: [Item] = []
    private var itemButtons: [UIButton] = []
    private var labels: [UILabel] = []
    private let closeButton = UIButton(configuration: UIButton.Configuration.filled())

    init(sections: [(title: String, items: [Item])]) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.5)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:))))

        panel.layer.cornerRadius = 20
        panel.layer.borderWidth = 2
        addSubview(panel)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        panel.addSubview(stack)

        addLabel("モニターを追加", size: 20, weight: .bold)
        for section in sections {
            addLabel(section.title, size: 13, weight: .semibold)
            var row: UIStackView?
            for (i, item) in section.items.enumerated() {
                if i % 3 == 0 {
                    let r = UIStackView()
                    r.axis = .horizontal
                    r.spacing = 10
                    r.distribution = .fillEqually
                    stack.addArrangedSubview(r)
                    row = r
                }
                var config = UIButton.Configuration.gray()
                config.title = item.title
                config.cornerStyle = .large
                config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10)
                let b = UIButton(configuration: config)
                b.tag = items.count
                b.addTarget(self, action: #selector(picked(_:)), for: .touchUpInside)
                items.append(item)
                itemButtons.append(b)
                row?.addArrangedSubview(b)
            }
            // 最後の行が3つに満たないときは、幅がそろうよう空白で埋める
            let rest = (3 - section.items.count % 3) % 3
            for _ in 0..<rest {
                row?.addArrangedSubview(UIView())
            }
        }

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.title = "閉じる"
        closeConfig.cornerStyle = .capsule
        closeButton.configuration = closeConfig
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        stack.addArrangedSubview(closeButton)

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    private func addLabel(_ text: String, size: CGFloat, weight: UIFont.Weight) {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        labels.append(l)
        stack.addArrangedSubview(l)
    }

    func applyTheme() {
        let t = Palette.theme
        panel.backgroundColor = t.panel
        panel.layer.borderColor = t.edge.cgColor
        for l in labels { l.textColor = t.ink }
        for b in itemButtons {
            var config = b.configuration
            config?.baseBackgroundColor = t.ink.withAlphaComponent(0.14)
            config?.baseForegroundColor = t.ink
            b.configuration = config
        }
        var closeConfig = closeButton.configuration
        closeConfig?.baseBackgroundColor = t.accent
        closeConfig?.baseForegroundColor = t.accentInk
        closeButton.configuration = closeConfig
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(560, bounds.width - 48)
        let inner = max(0, width - 48)
        let fit = stack.systemLayoutSizeFitting(
            CGSize(width: inner, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let height = fit.height + 48
        panel.frame = CGRect(x: (bounds.width - width) / 2, y: max(16, (bounds.height - height) / 2),
                             width: width, height: height)
        stack.frame = CGRect(x: 24, y: 24, width: inner, height: fit.height)
    }

    @objc private func picked(_ sender: UIButton) {
        if sender.tag >= 0 && sender.tag < items.count {
            onPick?(items[sender.tag].url)
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    /// パネルの外側をタップしたら閉じる
    @objc private func backgroundTapped(_ g: UITapGestureRecognizer) {
        if !panel.frame.contains(g.location(in: self)) {
            onClose?()
        }
    }
}

// MARK: - アプリ内キーボード（入力パネル）

/// システムのキーボードが出ないときの代わり。ゲーム機の文字入力のように、五十音の表から文字を選ぶ。
/// 上の入力欄をタップしてシステムのキーボードが出る場合は、そちらでも入力できる。
final class InputPanel: UIView, UITextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let column = UIStackView()
    private let titleLabel = UILabel()
    private let topRow = UIStackView()
    private let field = UITextField()
    private let keyArea = UIStackView()
    private var keyButtons: [UIButton] = []
    private var actionButtons: [UIButton] = []
    private var mode = 0            // 0: かな, 1: 英字, 2: 数字と記号
    private var katakana = false
    private var upper = false

    /// 「＿」は空きマス
    private static let kanaRows: [String] = [
        "あかさたなはまやらわ",
        "いきしちにひみ＿りを",
        "うくすつぬふむゆるん",
        "えけせてねへめ＿れー",
        "おこそとのほもよろ、"
    ]
    private static let abcRows: [String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let symbolRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "~"],
        [".", ",", "?", "!", "'", "#", "%", "+", "=", "_"]
    ]
    /// 「゛゜」を押すたびに、最後の文字をこの順で切り替える
    private static let voicedCycles: [String] = [
        "かが", "きぎ", "くぐ", "けげ", "こご", "さざ", "しじ", "すず", "せぜ", "そぞ",
        "ただ", "ちぢ", "つづ", "てで", "とど", "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ", "うゔ"
    ]
    /// 「小」を押すたびに、最後の文字を小さい字と切り替える
    private static let smallCycles: [String] = [
        "あぁ", "いぃ", "うぅ", "えぇ", "おぉ", "つっ", "やゃ", "ゆゅ", "よょ", "わゎ"
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.borderWidth = 2

        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 8
        addSubview(column)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        column.addArrangedSubview(titleLabel)

        topRow.axis = .horizontal
        topRow.alignment = .fill
        topRow.spacing = 8
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 18)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.clearButtonMode = .always
        field.overrideUserInterfaceStyle = .dark
        field.delegate = self
        field.addTarget(self, action: #selector(fieldEdited), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topRow.addArrangedSubview(field)
        topRow.addArrangedSubview(makeAction("貼り付け", #selector(pasteTapped)))
        topRow.addArrangedSubview(makeAction("決定", #selector(submitTapped)))
        topRow.addArrangedSubview(makeAction("閉じる", #selector(closeTapped)))
        topRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
        column.addArrangedSubview(topRow)

        keyArea.axis = .vertical
        keyArea.alignment = .fill
        keyArea.spacing = 6
        column.addArrangedSubview(keyArea)

        rebuildKeys()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    // MARK: 外から使うもの

    func open(title: String, text: String, secure: Bool) {
        titleLabel.text = title
        field.isSecureTextEntry = secure
        field.text = text
    }

    /// 上の入力欄にカーソルを入れる（システムのキーボードが使える環境なら、ここで出てくる）
    func beginInput() {
        field.becomeFirstResponder()
    }

    func endInput() {
        field.resignFirstResponder()
    }

    /// システムのキーボードが出ている間は、五十音のキーを隠す
    func setKeysHidden(_ hidden: Bool) {
        if keyArea.isHidden != hidden {
            keyArea.isHidden = hidden
        }
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        let fit = column.systemLayoutSizeFitting(
            CGSize(width: max(0, width - 28), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        return fit.height + 28
    }

    func applyTheme() {
        let t = Palette.theme
        backgroundColor = t.panel
        layer.borderColor = t.accent.cgColor
        titleLabel.textColor = t.ink
        for b in keyButtons {
            b.backgroundColor = t.ink.withAlphaComponent(0.14)
            b.setTitleColor(t.ink, for: .normal)
        }
        for b in actionButtons {
            b.backgroundColor = t.accent
            b.setTitleColor(t.accentInk, for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds.insetBy(dx: 14, dy: 14)
    }

    // MARK: キーの組み立て

    private func makeAction(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.layer.cornerRadius = 10
        b.addTarget(self, action: action, for: .touchUpInside)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButtons.append(b)
        return b
    }

    private func makeKey(_ title: String) -> UIView {
        if title == "＿" {
            return UIView()
        }
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        b.layer.cornerRadius = 8
        b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        keyButtons.append(b)
        return b
    }

    private func addRow(_ titles: [String]) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        for title in titles {
            row.addArrangedSubview(makeKey(title))
        }
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        keyArea.addArrangedSubview(row)
    }

    private func rebuildKeys() {
        for v in keyArea.arrangedSubviews {
            keyArea.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        keyButtons.removeAll()
        switch mode {
        case 1:
            for row in InputPanel.abcRows {
                var titles: [String] = []
                for ch in row {
                    titles.append(upper ? String(ch).uppercased() : String(ch))
                }
                addRow(titles)
            }
            addRow(["⇧", ".", "/", ":", "-", "_", "@", ".com", ".jp"])
        case 2:
            for row in InputPanel.symbolRows {
                addRow(row)
            }
        default:
            for row in InputPanel.kanaRows {
                var titles: [String] = []
                for ch in row {
                    titles.append(katakana ? toKatakana(String(ch)) : String(ch))
                }
                addRow(titles)
            }
            addRow(["゛゜", "小", katakana ? "ひらがな" : "カタカナ", "。", "？", "！"])
        }
        addRow(["かな", "ABC", "123", "空白", "⌫"])
        applyTheme()
        superview?.setNeedsLayout()
    }

    // MARK: 文字の処理

    private func toKatakana(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if u.value >= 0x3041 && u.value <= 0x3096, let k = Unicode.Scalar(u.value + 0x60) {
                out.append(k)
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    private func toHiragana(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if u.value >= 0x30A1 && u.value <= 0x30F6, let h = Unicode.Scalar(u.value - 0x60) {
                out.append(h)
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    /// 最後の1文字を、表の順に次の文字へ切り替える（濁点・半濁点・小さい字）
    private func cycleLast(_ text: String, _ cycles: [String]) -> String {
        guard let last = text.last else { return text }
        let lastString = String(last)
        // カタカナはひらがなに直して表を引き、結果をカタカナへ戻す
        let hira = toHiragana(lastString)
        let wasKatakana = hira != lastString
        for cycle in cycles {
            let chars = Array(cycle)
            for (i, ch) in chars.enumerated() where String(ch) == hira {
                let next = String(chars[(i + 1) % chars.count])
                return String(text.dropLast()) + (wasKatakana ? toKatakana(next) : next)
            }
        }
        return text
    }

    @objc private func keyTapped(_ sender: UIButton) {
        let key = sender.title(for: .normal) ?? ""
        var text = field.text ?? ""
        switch key {
        case "⌫":
            if !text.isEmpty { text.removeLast() }
        case "空白":
            text += " "
        case "゛゜":
            text = cycleLast(text, InputPanel.voicedCycles)
        case "小":
            text = cycleLast(text, InputPanel.smallCycles)
        case "カタカナ", "ひらがな":
            katakana.toggle()
            rebuildKeys()
            return
        case "⇧":
            upper.toggle()
            rebuildKeys()
            return
        case "かな":
            mode = 0
            rebuildKeys()
            return
        case "ABC":
            mode = 1
            rebuildKeys()
            return
        case "123":
            mode = 2
            rebuildKeys()
            return
        default:
            text += key
        }
        field.text = text
        onChange?(text)
    }

    @objc private func fieldEdited() {
        onChange?(field.text ?? "")
    }

    @objc private func pasteTapped() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else { return }
        let text = (field.text ?? "") + pasted
        field.text = text
        onChange?(text)
    }

    @objc private func submitTapped() {
        onSubmit?(field.text ?? "")
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?(textField.text ?? "")
        return false
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        onChange?("")
        return true
    }
}
