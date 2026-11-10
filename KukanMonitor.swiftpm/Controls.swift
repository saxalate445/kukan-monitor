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
