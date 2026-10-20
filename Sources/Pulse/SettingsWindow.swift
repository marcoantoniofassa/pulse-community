import AppKit

enum PulsePalette {
    static let background = NSColor(red: 0x12 / 255.0, green: 0x0c / 255.0, blue: 0x1c / 255.0, alpha: 1)
    static let panel = NSColor(red: 0x22 / 255.0, green: 0x18 / 255.0, blue: 0x30 / 255.0, alpha: 1)
    static let accent = NSColor(red: 0xb4 / 255.0, green: 0x4a / 255.0, blue: 0xff / 255.0, alpha: 1)
    static let text = NSColor(red: 0xf0 / 255.0, green: 0xea / 255.0, blue: 0xf8 / 255.0, alpha: 1)
    static let secondary = NSColor(red: 0x98 / 255.0, green: 0x86 / 255.0, blue: 0xad / 255.0, alpha: 1)
    static let muted = NSColor(red: 0x6b / 255.0, green: 0x5a / 255.0, blue: 0x80 / 255.0, alpha: 1)
    static let border = NSColor(red: 91 / 255.0, green: 45 / 255.0, blue: 142 / 255.0, alpha: 0.25)
}

final class SettingsWindow: NSWindow {
    private let state = StateManager.shared
    private var tableView: NSTableView!
    private var countLabel: NSTextField!
    private var dashboard: SavingsDashboardView!

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        title = "Pulse"
        minSize = NSSize(width: 560, height: 650)
        isReleasedWhenClosed = false
        center()
        setupContent()
    }

    private func setupContent() {
        let container = NSView(frame: contentRect(forFrameRect: frame))
        container.wantsLayer = true
        container.layer?.backgroundColor = PulsePalette.background.cgColor

        let headerHeight: CGFloat = 76
        let header = NSView(frame: NSRect(x: 0, y: container.bounds.height - headerHeight, width: container.bounds.width, height: headerHeight))
        header.autoresizingMask = [.width, .minYMargin]
        let titleLabel = label("Pulse", size: 21, weight: .bold, color: PulsePalette.text)
        titleLabel.frame = NSRect(x: 20, y: 38, width: 200, height: 28)
        header.addSubview(titleLabel)
        let subtitle = label("Seu painel de ditado", size: 11, weight: .regular, color: PulsePalette.secondary)
        subtitle.frame = NSRect(x: 20, y: 17, width: 250, height: 16)
        header.addSubview(subtitle)
        countLabel = label("", size: 11, weight: .medium, color: PulsePalette.muted)
        countLabel.alignment = .right
        countLabel.frame = NSRect(x: container.bounds.width - 190, y: 17, width: 170, height: 16)
        countLabel.autoresizingMask = [.minXMargin]
        header.addSubview(countLabel)
        container.addSubview(header)

        let separator = NSView(frame: NSRect(x: 0, y: container.bounds.height - headerHeight, width: container.bounds.width, height: 1))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = PulsePalette.border.cgColor
        separator.autoresizingMask = [.width, .minYMargin]
        container.addSubview(separator)

        let dashboardHeight: CGFloat = 430
        dashboard = SavingsDashboardView(state: state, frame: NSRect(x: 0, y: container.bounds.height - headerHeight - dashboardHeight, width: container.bounds.width, height: dashboardHeight))
        dashboard.autoresizingMask = [.width, .minYMargin]
        container.addSubview(dashboard)

        let bottomHeight: CGFloat = 42
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: bottomHeight, width: container.bounds.width, height: container.bounds.height - headerHeight - dashboardHeight - bottomHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        tableView = NSTableView()
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 48
        tableView.headerView = nil
        tableView.backgroundColor = PulsePalette.background
        tableView.addTableColumn(column("time", width: 70, minWidth: 60))
        tableView.addTableColumn(column("text", width: 300, minWidth: 200))
        tableView.addTableColumn(column("app", width: 100, minWidth: 60))
        tableView.delegate = self
        tableView.dataSource = self
        scrollView.documentView = tableView
        container.addSubview(scrollView)

        let bottom = NSView(frame: NSRect(x: 0, y: 0, width: container.bounds.width, height: bottomHeight))
        bottom.autoresizingMask = [.width, .maxYMargin]
        let clear = NSButton(title: "Limpar histórico", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .recessed
        clear.frame = NSRect(x: 20, y: 9, width: 130, height: 24)
        bottom.addSubview(clear)
        let copy = NSButton(title: "Copiar selecionado", target: self, action: #selector(copySelected))
        copy.bezelStyle = .recessed
        copy.frame = NSRect(x: 160, y: 9, width: 145, height: 24)
        bottom.addSubview(copy)
        container.addSubview(bottom)
        contentView = container
    }

    private func column(_ id: String, width: CGFloat, minWidth: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.width = width
        column.minWidth = minWidth
        return column
    }

    func refresh() {
        tableView?.reloadData()
        countLabel?.stringValue = "\(state.history.count) ditados no histórico"
        dashboard?.refresh()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Limpar histórico?"
        alert.informativeText = "Isso vai apagar todas as \(state.history.count) transcrições."
        alert.addButton(withTitle: "Limpar")
        alert.addButton(withTitle: "Cancelar")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            state.clearHistory()
            refresh()
        }
    }

    @objc private func copySelected() {
        let row = tableView.selectedRow
        guard let entry = (row >= 0 && row < state.history.count) ? state.history[row] : state.history.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
}

private final class SavingsDashboardView: NSView {
    private let state: StateManager
    private let periodControl = NSSegmentedControl(labels: ["Hoje", "Esta semana", "Tudo"], trackingMode: .selectOne, target: nil, action: nil)
    private let savedLabel = label("", size: 27, weight: .bold, color: PulsePalette.text)
    private let bars = ComparisonBarsView(frame: .zero)
    private var cardValues: [NSTextField] = []
    private let chart = SavingsChartView(frame: .zero)
    private let appsView = AppBreakdownView(frame: .zero)

    init(state: StateManager, frame: NSRect) {
        self.state = state
        super.init(frame: frame)
        wantsLayer = true
        periodControl.target = self
        periodControl.action = #selector(periodChanged)
        periodControl.selectedSegment = HistoryPeriod.week.rawValue
        periodControl.segmentStyle = .rounded
        addSubview(periodControl)
        addSubview(savedLabel)
        let savedCaption = label("TEMPO QUE VOCÊ NÃO PASSOU DIGITANDO", size: 10, weight: .semibold, color: PulsePalette.secondary)
        savedCaption.identifier = NSUserInterfaceItemIdentifier("savedCaption")
        addSubview(savedCaption)
        addSubview(bars)
        for title in ["MINUTOS DE ÁUDIO", "PALAVRAS DITADAS", "PALAVRAS POR MINUTO", "DITADOS"] {
            let card = StatCard(title: title)
            addSubview(card)
            cardValues.append(card.valueLabel)
        }
        addSubview(chart)
        addSubview(appsView)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = bounds.width
        periodControl.frame = NSRect(x: 20, y: bounds.height - 34, width: 250, height: 26)
        savedLabel.frame = NSRect(x: 20, y: bounds.height - 75, width: width - 40, height: 34)
        subviews.first(where: { $0.identifier?.rawValue == "savedCaption" })?.frame = NSRect(x: 20, y: bounds.height - 91, width: width - 40, height: 14)
        bars.frame = NSRect(x: 20, y: bounds.height - 145, width: width - 40, height: 46)
        let cardWidth = (width - 40 - 3 * 8) / 4
        for (index, card) in subviews.compactMap({ $0 as? StatCard }).enumerated() {
            card.frame = NSRect(x: 20 + CGFloat(index) * (cardWidth + 8), y: bounds.height - 215, width: cardWidth, height: 58)
        }
        chart.frame = NSRect(x: 20, y: 25, width: (width - 52) * 0.58, height: 165)
        appsView.frame = NSRect(x: chart.frame.maxX + 18, y: 25, width: width - chart.frame.maxX - 38, height: 165)
    }

    @objc private func periodChanged() { refresh() }

    func refresh() {
        let period = HistoryPeriod(rawValue: periodControl.selectedSegment) ?? .week
        let data = state.dashboard(for: period)
        savedLabel.stringValue = minutesText(max(0, data.savedMinutes))
        bars.typingMinutes = data.typingMinutes
        bars.speakingMinutes = data.audioMinutes
        cardValues[0].stringValue = String(format: "%.1f", data.audioMinutes)
        cardValues[1].stringValue = NumberFormatter.localizedString(from: NSNumber(value: data.wordCount), number: .decimal)
        cardValues[2].stringValue = String(format: "%.0f", data.wordsPerMinute)
        cardValues[3].stringValue = "\(data.entries.count)"
        chart.values = state.dailySavingsLastSevenDays()
        appsView.apps = Array(data.appCounts.prefix(5))
        needsLayout = true
        needsDisplay = true
    }

    private func minutesText(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        return whole >= 60 ? "\(whole / 60)h \(String(format: "%02d", whole % 60)) min" : "\(whole) min"
    }
}

private final class StatCard: NSView {
    let valueLabel = label("0", size: 18, weight: .bold, color: PulsePalette.text)
    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PulsePalette.panel.cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = PulsePalette.border.cgColor
        layer?.borderWidth = 1
        valueLabel.alignment = .center
        addSubview(valueLabel)
        let titleLabel = label(title, size: 8, weight: .semibold, color: PulsePalette.secondary)
        titleLabel.alignment = .center
        titleLabel.identifier = NSUserInterfaceItemIdentifier("title")
        addSubview(titleLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { valueLabel.frame = NSRect(x: 4, y: 25, width: bounds.width - 8, height: 24); subviews.first(where: { $0.identifier?.rawValue == "title" })?.frame = NSRect(x: 4, y: 8, width: bounds.width - 8, height: 12) }
}

private final class ComparisonBarsView: NSView {
    var typingMinutes = 0.0 { didSet { needsDisplay = true } }
    var speakingMinutes = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let maxValue = max(typingMinutes, speakingMinutes, 1)
        drawBar(name: "digitando", value: typingMinutes, y: 27, color: NSColor(red: 0x3d/255.0, green: 0x2f/255.0, blue: 0x52/255.0, alpha: 1), maxValue: maxValue, isSpeaking: false)
        drawBar(name: "falando", value: speakingMinutes, y: 5, color: PulsePalette.accent, maxValue: maxValue, isSpeaking: true)
    }
    private func drawBar(name: String, value: Double, y: CGFloat, color: NSColor, maxValue: Double, isSpeaking: Bool) {
        let labelRect = NSRect(x: 0, y: y, width: 70, height: 15)
        name.draw(in: labelRect, withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: PulsePalette.secondary])
        let track = NSRect(x: 76, y: y + 2, width: max(0, bounds.width - 135), height: 10)
        isSpeaking ? PulsePalette.border.setFill() : color.setFill()
        NSBezierPath(roundedRect: track, xRadius: 5, yRadius: 5).fill()
        let valueRect = NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(value / maxValue), height: track.height)
        if isSpeaking {
            NSGradient(starting: NSColor(red: 0x8b/255.0, green: 0x23/255.0, blue: 0xe5/255.0, alpha: 1), ending: PulsePalette.accent)?.draw(in: NSBezierPath(roundedRect: valueRect, xRadius: 5, yRadius: 5), angle: 0)
        } else {
            color.setFill(); NSBezierPath(roundedRect: valueRect, xRadius: 5, yRadius: 5).fill()
        }
        String(format: "%.1f min", value).draw(in: NSRect(x: track.maxX + 8, y: y, width: 55, height: 15), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: PulsePalette.secondary])
    }
}

private final class SavingsChartView: NSView {
    var values: [(date: Date, savedMinutes: Double)] = [] { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        "ECONOMIA: ÚLTIMOS 7 DIAS".draw(in: NSRect(x: 0, y: bounds.height - 15, width: bounds.width, height: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: PulsePalette.secondary])
        let maximum = max(values.map { max(0, $0.savedMinutes) }.max() ?? 0, 1)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "pt_BR"); formatter.dateFormat = "EE"
        let available = bounds.width / CGFloat(max(values.count, 1))
        for (index, item) in values.enumerated() {
            let x = CGFloat(index) * available + available * 0.2
            let height = CGFloat(max(0, item.savedMinutes) / maximum) * (bounds.height - 53)
            if height > 0.5 {
                PulsePalette.accent.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 23, width: available * 0.6, height: height), xRadius: 3, yRadius: 3).fill()
                String(format: "%.0f", item.savedMinutes).draw(in: NSRect(x: x - 5, y: 26 + height, width: available * 0.6 + 10, height: 12), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: PulsePalette.secondary])
            } else {
                "–".draw(in: NSRect(x: x, y: 26, width: available * 0.6, height: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: PulsePalette.muted])
            }
            formatter.string(from: item.date).capitalized.draw(in: NSRect(x: x - 5, y: 2, width: available * 0.6 + 10, height: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: PulsePalette.muted])
        }
    }
}

private final class AppBreakdownView: NSView {
    var apps: [(name: String, count: Int)] = [] { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        "ONDE VOCÊ MAIS DITOU".draw(in: NSRect(x: 0, y: bounds.height - 15, width: bounds.width, height: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: PulsePalette.secondary])
        guard let maxCount = apps.map(\.count).max(), maxCount > 0 else {
            "Ainda não há apps no período.".draw(in: NSRect(x: 0, y: 70, width: bounds.width, height: 15), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: PulsePalette.muted]); return
        }
        for (index, app) in apps.enumerated() {
            let y = bounds.height - 38 - CGFloat(index) * 25
            app.name.draw(in: NSRect(x: 0, y: y, width: bounds.width - 28, height: 13), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: PulsePalette.text])
            "\(app.count)".draw(in: NSRect(x: bounds.width - 24, y: y, width: 24, height: 13), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: PulsePalette.secondary])
            let bar = NSRect(x: 0, y: y - 6, width: (bounds.width - 2) * CGFloat(app.count) / CGFloat(maxCount), height: 3)
            PulsePalette.accent.withAlphaComponent(0.7).setFill(); NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { state.history.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < state.history.count else { return nil }
        let entry = state.history[row]
        let id = NSUserInterfaceItemIdentifier("cell_\(tableColumn?.identifier.rawValue ?? "")")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? NSTextField(labelWithString: "")
        cell.identifier = id; cell.lineBreakMode = .byTruncatingTail
        switch tableColumn?.identifier.rawValue {
        case "time": let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; cell.stringValue = formatter.string(from: entry.date); cell.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); cell.textColor = PulsePalette.secondary
        case "text": cell.stringValue = entry.text; cell.font = .systemFont(ofSize: 13); cell.textColor = PulsePalette.text; cell.toolTip = entry.text
        case "app": cell.stringValue = entry.app; cell.font = .systemFont(ofSize: 11); cell.textColor = PulsePalette.muted
        default: break
        }
        return cell
    }
}
