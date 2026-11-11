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

// MARK: - ローマ字→ひらがな変換

/// ローマ字入力をひらがなに変換する。漢字変換はしない（実在のIMEと同じ「かな」までの確定）。
enum RomajiKana {
    static let map: [String: String] = [
        "-": "ー", "a": "あ", "e": "え", "i": "い", "o": "お", "u": "う",
        "ba": "ば", "be": "べ", "bi": "び", "bo": "ぼ", "bu": "ぶ", "da": "だ",
        "de": "で", "di": "ぢ", "do": "ど", "du": "づ", "fa": "ふぁ", "fe": "ふぇ",
        "fi": "ふぃ", "fo": "ふぉ", "fu": "ふ", "ga": "が", "ge": "げ", "gi": "ぎ",
        "go": "ご", "gu": "ぐ", "ha": "は", "he": "へ", "hi": "ひ", "ho": "ほ",
        "hu": "ふ", "ja": "じゃ", "je": "じぇ", "ji": "じ", "jo": "じょ", "ju": "じゅ",
        "ka": "か", "ke": "け", "ki": "き", "ko": "こ", "ku": "く", "la": "ぁ",
        "le": "ぇ", "li": "ぃ", "lo": "ぉ", "lu": "ぅ", "ma": "ま", "me": "め",
        "mi": "み", "mo": "も", "mu": "む", "na": "な", "ne": "ね", "ni": "に",
        "no": "の", "nu": "ぬ", "pa": "ぱ", "pe": "ぺ", "pi": "ぴ", "po": "ぽ",
        "pu": "ぷ", "ra": "ら", "re": "れ", "ri": "り", "ro": "ろ", "ru": "る",
        "sa": "さ", "se": "せ", "si": "し", "so": "そ", "su": "す", "ta": "た",
        "te": "て", "ti": "ち", "to": "と", "tu": "つ", "va": "ゔぁ", "ve": "ゔぇ",
        "vi": "ゔぃ", "vo": "ゔぉ", "vu": "ゔ", "wa": "わ", "we": "うぇ", "wi": "うぃ",
        "wo": "を", "xa": "ぁ", "xe": "ぇ", "xi": "ぃ", "xo": "ぉ", "xu": "ぅ",
        "ya": "や", "yo": "よ", "yu": "ゆ", "za": "ざ", "ze": "ぜ", "zi": "じ",
        "zo": "ぞ", "zu": "ず", "bya": "びゃ", "byo": "びょ", "byu": "びゅ", "cha": "ちゃ",
        "che": "ちぇ", "chi": "ち", "cho": "ちょ", "chu": "ちゅ", "cya": "ちゃ", "cyo": "ちょ",
        "cyu": "ちゅ", "gya": "ぎゃ", "gyo": "ぎょ", "gyu": "ぎゅ", "hya": "ひゃ", "hyo": "ひょ",
        "hyu": "ひゅ", "jya": "じゃ", "jyo": "じょ", "jyu": "じゅ", "kya": "きゃ", "kyo": "きょ",
        "kyu": "きゅ", "ltu": "っ", "lwa": "ゎ", "lya": "ゃ", "lyo": "ょ", "lyu": "ゅ",
        "mya": "みゃ", "myo": "みょ", "myu": "みゅ", "nya": "にゃ", "nyo": "にょ", "nyu": "にゅ",
        "pya": "ぴゃ", "pyo": "ぴょ", "pyu": "ぴゅ", "rya": "りゃ", "ryo": "りょ", "ryu": "りゅ",
        "sha": "しゃ", "she": "しぇ", "shi": "し", "sho": "しょ", "shu": "しゅ", "sya": "しゃ",
        "syo": "しょ", "syu": "しゅ", "tha": "てゃ", "thi": "てぃ", "tsu": "つ", "tya": "ちゃ",
        "tyo": "ちょ", "tyu": "ちゅ", "xtu": "っ", "xya": "ゃ", "xyo": "ょ", "xyu": "ゅ",
        "zya": "じゃ", "zyo": "じょ", "zyu": "じゅ", "ltsu": "っ", "xtsu": "っ"
    ]
    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]
    private static func isConsonant(_ c: Character) -> Bool { c.isLetter && !vowels.contains(c) }

    /// ローマ字の並びを、確定できる先頭部分だけ変換する。残り（まだ決まらない部分）も返す。
    static func convert(_ s: String) -> (kana: String, rest: String) {
        let a = Array(s)
        let n = a.count
        var out = ""
        var i = 0
        while i < n {
            var matched = false
            var L = min(4, n - i)
            while L >= 1 {
                if let k = map[String(a[i ..< i + L])] {
                    out += k
                    i += L
                    matched = true
                    break
                }
                L -= 1
            }
            if matched { continue }
            let c = a[i]
            let nxt: Character? = i + 1 < n ? a[i + 1] : nil
            if c == "n" {
                guard let nx = nxt else { break }
                if vowels.contains(nx) || nx == "y" { break }
                if nx == "'" { out += "ん"; i += 2; continue }
                if nx == "n" {
                    let after: Character? = i + 2 < n ? a[i + 2] : nil
                    if let af = after, vowels.contains(af) || af == "y" {
                        out += "ん"; i += 1
                    } else {
                        out += "ん"; i += 2
                    }
                    continue
                }
                out += "ん"; i += 1; continue
            }
            if let nx = nxt, nx == c, isConsonant(c) {
                out += "っ"; i += 1; continue
            }
            break
        }
        return (out, String(a[i ..< n]))
    }

    static func toKatakana(_ s: String) -> String {
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
}

// MARK: - アプリ内キーボード（入力パネル）

/// システムのキーボードが出ないときの代わり。パソコンと同じ QWERTY 配列で、ローマ字を打つとひらがなになる。
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
    private var funcButtons: [UIButton] = []
    private var actionButtons: [UIButton] = []

    private var mode = 0            // 0: かな（ローマ字）, 1: ABC（英字）, 2: 123（数字と記号）
    private var katakana = false
    private var upper = false
    private var committed = ""      // 確定した文字（かな・英字・記号・空白）
    private var romaji = ""         // 変換前のローマ字（かなモードのみ）
    private var settingProgrammatically = false

    private static let kanaRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m", "⌫"],
        ["ABC", "123", "カナ", "空白", "ー", "。", "、"]
    ]
    private static let abcRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
        ["かな", "123", "@", ".", "/", "空白", ".com"]
    ]
    private static let numRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""],
        [".", ",", "?", "!", "'", "#", "%", "+", "=", "⌫"],
        ["かな", "ABC", "空白", "。", "、"]
    ]
    private static let functionTitles: Set<String> = ["⌫", "空白", "⇧", "かな", "ABC", "123", "カナ", "カタカナ", "ひらがな", ".com"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.borderWidth = 2

        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 8
        addSubview(column)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.numberOfLines = 1
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
        committed = text
        romaji = ""
        mode = 0
        upper = false
        katakana = false
        field.isSecureTextEntry = secure
        settingProgrammatically = true
        field.text = text
        settingProgrammatically = false
        rebuildKeys()
    }

    /// 上の入力欄にカーソルを入れる（システムのキーボードが使える環境なら、ここで出てくる）
    func beginInput() {
        field.becomeFirstResponder()
    }

    func endInput() {
        field.resignFirstResponder()
    }

    /// システムのキーボードが出ている間は、QWERTYのキーを隠す（上の入力欄だけ使う）
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
        for b in funcButtons {
            b.backgroundColor = t.accent.withAlphaComponent(0.22)
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

    private func makeKey(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.6
        b.layer.cornerRadius = 8
        b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        if InputPanel.functionTitles.contains(title) {
            funcButtons.append(b)
        } else {
            keyButtons.append(b)
        }
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
        row.heightAnchor.constraint(equalToConstant: 42).isActive = true
        keyArea.addArrangedSubview(row)
    }

    private func rebuildKeys() {
        for v in keyArea.arrangedSubviews {
            keyArea.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        keyButtons.removeAll()
        funcButtons.removeAll()
        let rows: [[String]]
        switch mode {
        case 1: rows = InputPanel.abcRows
        case 2: rows = InputPanel.numRows
        default: rows = InputPanel.kanaRows
        }
        for row in rows {
            var titles: [String] = []
            for key in row {
                if key == "カナ" {
                    titles.append(katakana ? "ひらがな" : "カタカナ")
                } else if mode == 1 && key.count == 1, let ch = key.first, ch.isLetter {
                    titles.append(upper ? key.uppercased() : key)
                } else {
                    titles.append(key)
                }
            }
            addRow(titles)
        }
        applyTheme()
        superview?.setNeedsLayout()
    }

    // MARK: 文字の処理

    private func preview() -> String {
        let (k, rest) = RomajiKana.convert(romaji)
        return (katakana ? RomajiKana.toKatakana(k) : k) + rest
    }

    /// ローマ字の未確定分をかなにして確定する（末尾の n は ん）
    private func flushRomaji() {
        guard !romaji.isEmpty else { return }
        let (k, rest) = RomajiKana.convert(romaji)
        var add = katakana ? RomajiKana.toKatakana(k) : k
        if rest == "n" {
            add += katakana ? "ン" : "ん"
        } else {
            add += rest
        }
        committed += add
        romaji = ""
    }

    private func updateField() {
        settingProgrammatically = true
        field.text = committed + preview()
        settingProgrammatically = false
        onChange?(field.text ?? "")
    }

    private func switchMode(_ m: Int) {
        flushRomaji()
        mode = m
        if m != 1 { upper = false }
        rebuildKeys()
    }

    @objc private func keyTapped(_ sender: UIButton) {
        let key = sender.title(for: .normal) ?? ""
        switch key {
        case "⌫":
            if !romaji.isEmpty {
                romaji.removeLast()
            } else if !committed.isEmpty {
                committed.removeLast()
            }
            updateField()
        case "空白":
            flushRomaji()
            committed += " "
            updateField()
        case "⇧":
            upper.toggle()
            rebuildKeys()
        case "カタカナ", "ひらがな":
            katakana.toggle()
            rebuildKeys()
            updateField()
        case "かな":
            switchMode(0)
        case "ABC":
            switchMode(1)
        case "123":
            switchMode(2)
        case ".com":
            flushRomaji()
            committed += ".com"
            updateField()
        default:
            if mode == 0, key.count == 1, let ch = key.first, ch.isLetter, ch.isLowercase {
                romaji += key
                updateField()
            } else {
                flushRomaji()
                committed += key
                updateField()
            }
        }
    }

    @objc private func fieldEdited() {
        if settingProgrammatically { return }
        // システムのキーボードで直接打たれたときは、その内容を正とする
        committed = field.text ?? ""
        romaji = ""
        onChange?(field.text ?? "")
    }

    @objc private func pasteTapped() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else { return }
        flushRomaji()
        committed += pasted
        updateField()
    }

    @objc private func submitTapped() {
        flushRomaji()
        onSubmit?(committed)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        flushRomaji()
        onSubmit?(committed)
        return false
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        committed = ""
        romaji = ""
        onChange?("")
        return true
    }
}
