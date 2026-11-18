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

    private let glass = GlassView(cornerRadius: 54)
    private let ring = CAShapeLayer()
    private let dots = CAShapeLayer()
    private let hotDots = CAShapeLayer()
    private let me = CAShapeLayer()
    private var blips: [Blip] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.isUserInteractionEnabled = false
        addSubview(glass)
        ring.lineWidth = 1
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
        glass.applyTheme()
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor(white: 1, alpha: 0.16).cgColor
        dots.fillColor = Palette.ink.withAlphaComponent(0.85).cgColor
        hotDots.fillColor = Palette.accent.cgColor
        me.fillColor = Palette.accent.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        glass.frame = b
        glass.setCornerRadius(b.width / 2)
        // 内側の目盛りの輪（距離の目安）
        ring.path = CGPath(ellipseIn: b.insetBy(dx: b.width * 0.25, dy: b.height * 0.25), transform: nil)
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

    private let panel = GlassView(cornerRadius: 26)
    private let stack = UIStackView()
    private var items: [Item] = []
    private var itemButtons: [UIButton] = []
    private var labels: [UILabel] = []
    private let closeButton = UIButton(configuration: UIButton.Configuration.filled())

    init(title: String = "モニターを追加", sections: [(title: String, items: [Item])]) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.3)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:))))

        addSubview(panel)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        panel.contentView.addSubview(stack)

        addLabel(title, size: 20, weight: .bold)
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
        panel.applyTheme()
        for l in labels { l.textColor = t.ink }
        for b in itemButtons {
            var config = b.configuration
            config?.baseBackgroundColor = UIColor(white: 1, alpha: 0.13)
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

/// システムのキーボードが出ないときの代わり。iPadの英語キーボードと同じ比率の QWERTY 配列で、
/// ローマ字を打つとひらがなになる。上の入力欄でシステムのキーボードが出る場合は、そちらでも入力できる。
final class InputPanel: UIView, UITextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onClose: (() -> Void)?

    /// キー1つ分。title が空なら、幅だけ取る空き（2段目の左のずれなど）。
    private struct Key {
        let title: String
        let units: CGFloat
    }

    private let glass = GlassView(cornerRadius: 24)
    private let titleLabel = UILabel()
    private let topRow = UIStackView()
    private let field = UITextField()
    private let keyArea = UIView()
    private var keyRows: [[(view: UIButton?, units: CGFloat)]] = []
    private var keyButtons: [UIButton] = []
    private var funcButtons: [UIButton] = []
    private var actionButtons: [UIButton] = []

    private var mode = 0            // 0: かな（ローマ字）, 1: ABC（英字）, 2: 123（数字と記号）
    private var katakana = false
    private var upper = false
    private var committed = ""      // 確定した文字（かな・英字・記号・空白）
    private var romaji = ""         // 変換前のローマ字（かなモードのみ）
    private var settingProgrammatically = false

    // 1段の合計は、どのモードでも 11.5 キー分（iPadの英語キーボードの1段目＝10キー＋⌫ 1.5）
    private static let rowUnits: CGFloat = 11.5
    private static let gap: CGFloat = 7
    private static let rowGap: CGFloat = 8

    private static func letters(_ s: String) -> [Key] {
        s.map { Key(title: String($0), units: 1) }
    }

    private static let kanaRows: [[Key]] = [
        InputPanel.letters("qwertyuiop") + [Key(title: "⌫", units: 1.5)],
        [Key(title: "", units: 0.5)] + InputPanel.letters("asdfghjkl") + [Key(title: "決定", units: 2)],
        [Key(title: "カナ", units: 1.5)] + InputPanel.letters("zxcvbnm") + InputPanel.letters("、。ー"),
        [Key(title: "123", units: 1.5), Key(title: "ABC", units: 1.5), Key(title: "空白", units: 6.5),
         Key(title: "？", units: 1), Key(title: "！", units: 1)]
    ]
    private static let abcRows: [[Key]] = [
        InputPanel.letters("qwertyuiop") + [Key(title: "⌫", units: 1.5)],
        [Key(title: "", units: 0.5)] + InputPanel.letters("asdfghjkl") + [Key(title: "決定", units: 2)],
        [Key(title: "⇧", units: 1.5)] + InputPanel.letters("zxcvbnm") + InputPanel.letters(",./"),
        [Key(title: "123", units: 1.5), Key(title: "かな", units: 1.5), Key(title: "@", units: 1),
         Key(title: "空白", units: 5.5), Key(title: ".com", units: 2)]
    ]
    private static let numRows: [[Key]] = [
        InputPanel.letters("1234567890") + [Key(title: "⌫", units: 1.5)],
        [Key(title: "", units: 0.5)] + InputPanel.letters("-/:;()¥&@") + [Key(title: "決定", units: 2)],
        InputPanel.letters(".,?!'\"#%+=") + [Key(title: "~", units: 1.5)],
        [Key(title: "ABC", units: 1.5), Key(title: "かな", units: 1.5), Key(title: "空白", units: 6.5),
         Key(title: "。", units: 1), Key(title: "、", units: 1)]
    ]
    private static let functionTitles: Set<String> = ["⌫", "空白", "⇧", "かな", "ABC", "123", "カナ", "カタカナ", "ひらがな", ".com", "決定"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(glass)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.numberOfLines = 1
        glass.contentView.addSubview(titleLabel)

        topRow.axis = .horizontal
        topRow.alignment = .fill
        topRow.spacing = 8
        field.borderStyle = .none
        field.font = .systemFont(ofSize: 18)
        field.textColor = .white
        field.backgroundColor = UIColor(white: 0, alpha: 0.28)
        field.layer.cornerRadius = 10
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 10))
        field.leftViewMode = .always
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
        topRow.addArrangedSubview(makeAction("閉じる", #selector(closeTapped)))
        glass.contentView.addSubview(topRow)

        glass.contentView.addSubview(keyArea)

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
            setNeedsLayout()
        }
    }

    /// 1キー分の幅から決める、キーの高さ（実物のiPadと同じく、ほぼ正方形）
    private func keyHeight(width: CGFloat) -> CGFloat {
        let unit = (width - InputPanel.gap * 10) / InputPanel.rowUnits
        return min(66, max(40, unit * 0.92))
    }

    private func keysHeight(width: CGFloat) -> CGFloat {
        let rows = CGFloat(keyRows.count)
        return rows * keyHeight(width: width) + max(0, rows - 1) * InputPanel.rowGap
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        let inner = max(0, width - 36)
        var h: CGFloat = 18 + 18 + 10 + 44
        if !keyArea.isHidden {
            h += 14 + keysHeight(width: inner)
        }
        return h + 18
    }

    func applyTheme() {
        let t = Palette.theme
        glass.applyTheme()
        titleLabel.textColor = t.ink.withAlphaComponent(0.8)
        for b in keyButtons {
            b.backgroundColor = UIColor(white: 1, alpha: 0.2)
            b.setTitleColor(.white, for: .normal)
        }
        for b in funcButtons {
            b.backgroundColor = UIColor(white: 1, alpha: 0.08)
            b.setTitleColor(.white, for: .normal)
        }
        for b in actionButtons {
            b.backgroundColor = UIColor(white: 1, alpha: 0.14)
            b.setTitleColor(.white, for: .normal)
        }
        // 決定キーだけは目立たせる（iPadの「改行」キーの位置と大きさ）
        for row in keyRows {
            for item in row {
                if let b = item.view, b.title(for: .normal) == "決定" {
                    b.backgroundColor = t.accent
                    b.setTitleColor(t.accentInk, for: .normal)
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let inner = bounds.insetBy(dx: 18, dy: 18)
        titleLabel.frame = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 18)
        topRow.frame = CGRect(x: inner.minX, y: inner.minY + 28, width: inner.width, height: 44)
        if !keyArea.isHidden {
            let w = inner.width
            keyArea.frame = CGRect(x: inner.minX, y: topRow.frame.maxY + 14, width: w, height: keysHeight(width: w))
            layoutKeys(width: w)
        }
    }

    /// 段ごとに、キーの「何キー分の幅か」に合わせて並べる
    private func layoutKeys(width: CGFloat) {
        let h = keyHeight(width: width)
        var y: CGFloat = 0
        for row in keyRows {
            let units = row.reduce(CGFloat(0)) { $0 + $1.units }
            let gaps = InputPanel.gap * CGFloat(max(0, row.count - 1))
            let unitW = units > 0 ? (width - gaps) / units : 0
            var x: CGFloat = 0
            for item in row {
                let w = item.units * unitW
                item.view?.frame = CGRect(x: x, y: y, width: w, height: h)
                x += w + InputPanel.gap
            }
            y += h + InputPanel.rowGap
        }
    }

    // MARK: キーの組み立て

    private func makeAction(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.layer.cornerRadius = 10
        b.layer.cornerCurve = .continuous
        b.addTarget(self, action: action, for: .touchUpInside)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButtons.append(b)
        return b
    }

    private func makeKey(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        let isFunction = InputPanel.functionTitles.contains(title)
        b.titleLabel?.font = .systemFont(ofSize: isFunction ? 16 : 22, weight: isFunction ? .medium : .regular)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.6
        b.layer.cornerRadius = 8
        b.layer.cornerCurve = .continuous
        // 実物のキーのような、下側のわずかな影
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.25
        b.layer.shadowRadius = 0
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        if isFunction {
            funcButtons.append(b)
        } else {
            keyButtons.append(b)
        }
        return b
    }

    private func rebuildKeys() {
        for v in keyArea.subviews {
            v.removeFromSuperview()
        }
        keyRows.removeAll()
        keyButtons.removeAll()
        funcButtons.removeAll()
        let rows: [[Key]]
        switch mode {
        case 1: rows = InputPanel.abcRows
        case 2: rows = InputPanel.numRows
        default: rows = InputPanel.kanaRows
        }
        for row in rows {
            var built: [(view: UIButton?, units: CGFloat)] = []
            for key in row {
                if key.title.isEmpty {
                    built.append((view: nil, units: key.units))
                    continue
                }
                var title = key.title
                if title == "カナ" {
                    title = katakana ? "ひらがな" : "カタカナ"
                } else if mode == 1 && title.count == 1, let ch = title.first, ch.isLetter, upper {
                    title = title.uppercased()
                }
                let b = makeKey(title)
                keyArea.addSubview(b)
                built.append((view: b, units: key.units))
            }
            keyRows.append(built)
        }
        applyTheme()
        setNeedsLayout()
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
        case "決定":
            submitTapped()
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
            if mode == 0, key.count == 1, let ch = key.first, ch.isASCII, ch.isLetter, ch.isLowercase {
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

// MARK: - 照明の色（RGB）

/// 家具や空中の線を照らす光の色を、R・G・B と明るさのスライダーで選ぶパネル
final class LightPanel: UIView {
    var onChange: ((UIColor, Double) -> Void)?
    var onReset: (() -> Void)?
    var onClose: (() -> Void)?

    private let glass = GlassView(cornerRadius: 24)
    private let titleLabel = UILabel()
    private let swatch = UIView()
    private let hexLabel = UILabel()
    private var sliders: [UISlider] = []
    private var nameLabels: [UILabel] = []
    private var valueLabels: [UILabel] = []
    private let resetButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private static let names = ["R（赤）", "G（緑）", "B（青）", "明るさ"]
    private static let rowHeight: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glass)
        titleLabel.text = "空間の色（空・床・照明）"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        glass.contentView.addSubview(titleLabel)
        swatch.layer.cornerRadius = 12
        swatch.layer.cornerCurve = .continuous
        swatch.layer.borderWidth = 1
        swatch.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
        glass.contentView.addSubview(swatch)
        hexLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        glass.contentView.addSubview(hexLabel)
        for (i, name) in LightPanel.names.enumerated() {
            let n = UILabel()
            n.text = name
            n.font = .systemFont(ofSize: 14, weight: .medium)
            glass.contentView.addSubview(n)
            nameLabels.append(n)
            let s = UISlider()
            if i < 3 {
                s.minimumValue = 0
                s.maximumValue = 255
            } else {
                s.minimumValue = 0.2
                s.maximumValue = 2
            }
            s.addTarget(self, action: #selector(changed), for: .valueChanged)
            glass.contentView.addSubview(s)
            sliders.append(s)
            let v = UILabel()
            v.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
            v.textAlignment = .right
            glass.contentView.addSubview(v)
            valueLabels.append(v)
        }
        sliders[0].minimumTrackTintColor = UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
        sliders[1].minimumTrackTintColor = UIColor(red: 0.35, green: 0.9, blue: 0.45, alpha: 1)
        sliders[2].minimumTrackTintColor = UIColor(red: 0.4, green: 0.6, blue: 1, alpha: 1)
        for (b, title, action) in [(resetButton, "テーマの色に戻す", #selector(resetTapped)),
                                   (closeButton, "閉じる", #selector(closeTapped))] {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.layer.cornerRadius = 10
            b.layer.cornerCurve = .continuous
            b.addTarget(self, action: action, for: .touchUpInside)
            glass.contentView.addSubview(b)
        }
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    /// いまの色と明るさをスライダーに映す
    func set(color: UIColor, level: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
        sliders[0].value = Float(r * 255)
        sliders[1].value = Float(g * 255)
        sliders[2].value = Float(b * 255)
        sliders[3].value = Float(level)
        refreshLabels()
    }

    private var currentColor: UIColor {
        UIColor(red: CGFloat(sliders[0].value.rounded()) / 255, green: CGFloat(sliders[1].value.rounded()) / 255,
                blue: CGFloat(sliders[2].value.rounded()) / 255, alpha: 1)
    }

    private func refreshLabels() {
        for i in 0 ..< 3 {
            valueLabels[i].text = String(Int(sliders[i].value.rounded()))
        }
        valueLabels[3].text = String(format: "%.1f", sliders[3].value)
        swatch.backgroundColor = currentColor
        hexLabel.text = String(format: "#%02X%02X%02X", Int(sliders[0].value.rounded()),
                               Int(sliders[1].value.rounded()), Int(sliders[2].value.rounded()))
    }

    @objc private func changed() {
        refreshLabels()
        onChange?(currentColor, Double(sliders[3].value))
    }

    @objc private func resetTapped() { onReset?() }
    @objc private func closeTapped() { onClose?() }

    func applyTheme() {
        let t = Palette.theme
        glass.applyTheme()
        titleLabel.textColor = t.ink
        hexLabel.textColor = t.ink
        for l in nameLabels + valueLabels {
            l.textColor = t.ink.withAlphaComponent(0.85)
        }
        sliders[3].minimumTrackTintColor = t.accent
        resetButton.backgroundColor = UIColor(white: 1, alpha: 0.14)
        resetButton.setTitleColor(t.ink, for: .normal)
        closeButton.backgroundColor = t.accent
        closeButton.setTitleColor(t.accentInk, for: .normal)
    }

    var preferredHeight: CGFloat {
        20 + 34 + 12 + CGFloat(sliders.count) * LightPanel.rowHeight + 14 + 44 + 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let x: CGFloat = 20
        let w = bounds.width - 40
        titleLabel.frame = CGRect(x: x, y: 20, width: w - 140, height: 34)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        swatch.frame = CGRect(x: x + w - 34, y: 20, width: 34, height: 34)
        hexLabel.frame = CGRect(x: x + w - 34 - 96, y: 20, width: 88, height: 34)
        hexLabel.textAlignment = .right
        var y: CGFloat = 20 + 34 + 12
        for i in 0 ..< sliders.count {
            nameLabels[i].frame = CGRect(x: x, y: y, width: 70, height: LightPanel.rowHeight)
            valueLabels[i].frame = CGRect(x: x + w - 44, y: y, width: 44, height: LightPanel.rowHeight)
            sliders[i].frame = CGRect(x: x + 78, y: y, width: max(0, w - 78 - 52), height: LightPanel.rowHeight)
            y += LightPanel.rowHeight
        }
        y += 14
        let half = (w - 10) / 2
        resetButton.frame = CGRect(x: x, y: y, width: half, height: 44)
        closeButton.frame = CGRect(x: x + half + 10, y: y, width: half, height: 44)
    }
}

// MARK: - 収納・呼び寄せ

/// 空間にあるモニターと家具の一覧。遠くにあるものも、ここから「しまう／出す」「ここへ呼ぶ」ができる。
final class InventoryPanel: UIView {
    struct Row {
        let title: String
        let detail: String
        let stored: Bool
        let onBring: () -> Void
        let onToggle: () -> Void
    }

    var onClose: (() -> Void)?

    private let glass = GlassView(cornerRadius: 24)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var rows: [Row] = []
    private var rowButtons: [UIButton] = []
    private var rowLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glass)
        titleLabel.text = "収納・呼び寄せ"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        glass.contentView.addSubview(titleLabel)
        closeButton.setTitle("閉じる", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.layer.cornerRadius = 10
        closeButton.layer.cornerCurve = .continuous
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        glass.contentView.addSubview(closeButton)
        scroll.alwaysBounceVertical = true
        scroll.indicatorStyle = .white
        glass.contentView.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 8
        scroll.addSubview(stack)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使いません")
    }

    func reload(_ list: [Row]) {
        rows = list
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        rowButtons = []
        rowLabels = []
        if list.isEmpty {
            let empty = UILabel()
            empty.text = "モニターも家具もありません。"
            empty.font = .systemFont(ofSize: 15)
            rowLabels.append(empty)
            stack.addArrangedSubview(empty)
        }
        for (i, row) in list.enumerated() {
            let line = UIStackView()
            line.axis = .horizontal
            line.spacing = 8
            line.alignment = .center
            let label = UILabel()
            label.numberOfLines = 2
            let text = NSMutableAttributedString(string: row.title,
                                                 attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)])
            text.append(NSAttributedString(string: "\n" + row.detail,
                                           attributes: [.font: UIFont.systemFont(ofSize: 12)]))
            label.attributedText = text
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            rowLabels.append(label)
            line.addArrangedSubview(label)
            let bring = makeButton("ここへ", tag: i * 2)
            let toggle = makeButton(row.stored ? "出す" : "しまう", tag: i * 2 + 1)
            line.addArrangedSubview(bring)
            line.addArrangedSubview(toggle)
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            stack.addArrangedSubview(line)
        }
        applyTheme()
        setNeedsLayout()
    }

    private func makeButton(_ title: String, tag: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.layer.cornerRadius = 10
        b.layer.cornerCurve = .continuous
        b.tag = tag
        b.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 72).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        rowButtons.append(b)
        return b
    }

    @objc private func rowTapped(_ sender: UIButton) {
        let i = sender.tag / 2
        guard i >= 0 && i < rows.count else { return }
        if sender.tag % 2 == 0 {
            rows[i].onBring()
        } else {
            rows[i].onToggle()
        }
    }

    @objc private func closeTapped() { onClose?() }

    func applyTheme() {
        let t = Palette.theme
        glass.applyTheme()
        titleLabel.textColor = t.ink
        closeButton.backgroundColor = t.accent
        closeButton.setTitleColor(t.accentInk, for: .normal)
        for l in rowLabels {
            l.textColor = t.ink
        }
        for b in rowButtons {
            b.backgroundColor = UIColor(white: 1, alpha: 0.14)
            b.setTitleColor(t.ink, for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let x: CGFloat = 20
        let w = bounds.width - 40
        titleLabel.frame = CGRect(x: x, y: 18, width: w - 100, height: 36)
        closeButton.frame = CGRect(x: x + w - 88, y: 18, width: 88, height: 36)
        scroll.frame = CGRect(x: x, y: 66, width: w, height: max(0, bounds.height - 84))
        let fit = stack.systemLayoutSizeFitting(
            CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 0, y: 0, width: w, height: fit.height)
        scroll.contentSize = CGSize(width: w, height: fit.height)
    }
}
