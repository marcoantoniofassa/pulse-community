import AppKit
import AVFoundation
import Speech
import IOKit.hid

final class HelpWindow: NSWindow, NSWindowDelegate {

    // Ritmo vertical. Layout e todo frame-based e calculado de cima pra baixo:
    // NSStackView com subviews frame-based ja colapsou esta tela duas vezes
    // (ele zera translatesAutoresizingMaskIntoConstraints e as filhas ficam sem
    // tamanho). Frame puro e previsivel e nao tem essa classe de defeito.
    private enum L {
        static let width: CGFloat = 620
        static let pad: CGFloat = 28
        static let iconSize: CGFloat = 44
        static let introH: CGFloat = 38
        static let gapSecao: CGFloat = 26
        static let tituloH: CGFloat = 14
        static let gapTitulo: CGFloat = 12
        static let atalhoH: CGFloat = 34
        static let atalhoGap: CGFloat = 8
        static let permH: CGFloat = 42
        static let permGap: CGFloat = 6
        static let vocabH: CGFloat = 40
        static let footerH: CGFloat = 56

        static var altura: CGFloat {
            pad + iconSize + 16 + introH
            + gapSecao + tituloH + gapTitulo + (atalhoH * 4 + atalhoGap * 3)
            + gapSecao + tituloH + gapTitulo + (permH * 4 + permGap * 3)
            + gapSecao + vocabH
            + 18 + footerH
        }
    }

    private var permissoesArea: NSView!

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: L.width, height: L.altura),
                   styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = "Como usar o Pulse"
        isReleasedWhenClosed = false
        center()
        delegate = self
        setupContent()
        refreshPermissions()
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshPermissions() }

    private func setupContent() {
        let container = NSView(frame: contentRect(forFrameRect: frame))
        container.wantsLayer = true
        container.layer?.backgroundColor = PulsePalette.background.cgColor
        let W = container.bounds.width
        var y = container.bounds.height - L.pad   // cursor: desce conforme empilha

        // Cabecalho
        y -= L.iconSize
        container.addSubview(PulseWaveIconView(frame: NSRect(x: L.pad, y: y, width: L.iconSize, height: L.iconSize)))
        let titulo = label("Pulse", size: 26, weight: .bold, color: PulsePalette.text)
        titulo.frame = NSRect(x: L.pad + L.iconSize + 14, y: y + 20, width: 260, height: 32)
        container.addSubview(titulo)
        let versao = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versaoLabel = label("Versão \(versao)", size: 11, weight: .medium, color: PulsePalette.secondary)
        versaoLabel.frame = NSRect(x: L.pad + L.iconSize + 16, y: y + 3, width: 260, height: 15)
        container.addSubview(versaoLabel)

        y -= 16 + L.introH
        let intro = label("O Pulse fica na barra de menu e escreve onde o cursor já está.\nNão precisa abrir nada.",
                          size: 13, weight: .regular, color: PulsePalette.text)
        intro.frame = NSRect(x: L.pad, y: y, width: W - L.pad * 2, height: L.introH)
        intro.maximumNumberOfLines = 2
        container.addSubview(intro)

        // Atalhos
        y -= L.gapSecao + L.tituloH
        container.addSubview(tituloSecao("ATALHOS", y: y, width: W))
        y -= L.gapTitulo
        let atalhos: [(keys: [String], titulo: String, detalhe: String)] = [
            (["⌥", "⌥"], "Gravar e colar", "Fala tudo, para, e o texto cai de uma vez."),
            (["⌥", "S"], "Gravar e colar (alternativo)", "Use se o duplo Option não pegar."),
            (["⌥", "Space"], "Tempo real", "As palavras aparecem enquanto você fala."),
            (["esc"], "Cancelar", "Para a gravação na hora."),
        ]
        for atalho in atalhos {
            y -= L.atalhoH
            container.addSubview(linhaAtalho(atalho.keys, atalho.titulo, atalho.detalhe, y: y, width: W))
            y -= L.atalhoGap
        }
        y += L.atalhoGap

        // Permissoes (area redesenhada a cada foco: o usuario sai pra conceder e volta)
        y -= L.gapSecao + L.tituloH
        container.addSubview(tituloSecao("PERMISSÕES DO macOS", y: y, width: W))
        y -= L.gapTitulo
        let alturaPerm = L.permH * 4 + L.permGap * 3
        y -= alturaPerm
        permissoesArea = NSView(frame: NSRect(x: 0, y: y, width: W, height: alturaPerm))
        permissoesArea.autoresizingMask = [.width]
        container.addSubview(permissoesArea)

        // Vocabulario
        y -= L.gapSecao + L.vocabH
        container.addSubview(blocoVocabulario(y: y, width: W))

        // Rodape
        container.addSubview(rodape(width: W))
        contentView = container
    }

    /// Nome falado de cada tecla. O simbolo sozinho o VoiceOver le mal ou nao le.
    private static func nomeDaTecla(_ key: String) -> String {
        switch key {
        case "⌥": return "Option"
        case "esc": return "Escape"
        case "Space": return "Espaço"
        default: return key
        }
    }

    private func tituloSecao(_ texto: String, y: CGFloat, width: CGFloat) -> NSTextField {
        let t = label(texto, size: 10, weight: .bold, color: PulsePalette.secondary)
        t.frame = NSRect(x: L.pad, y: y, width: width - L.pad * 2, height: L.tituloH)
        return t
    }

    private func linhaAtalho(_ keys: [String], _ titulo: String, _ detalhe: String, y: CGFloat, width: CGFloat) -> NSView {
        let linha = NSView(frame: NSRect(x: 0, y: y, width: width, height: L.atalhoH))
        linha.autoresizingMask = [.width]
        // VoiceOver: a linha inteira e um elemento so. Sem isso ele le "Option",
        // "Space" e o titulo soltos, sem dizer que formam um atalho.
        linha.setAccessibilityElement(true)
        linha.setAccessibilityRole(.staticText)
        let falado = keys == ["⌥", "⌥"] ? "Option duas vezes" : keys.map(Self.nomeDaTecla).joined(separator: " mais ")
        linha.setAccessibilityLabel("Atalho \(falado): \(titulo). \(detalhe)")
        var x = L.pad
        for key in keys {
            let cap = KeyCapView(key: key)
            cap.setFrameOrigin(NSPoint(x: x, y: (L.atalhoH - cap.frame.height) / 2))
            linha.addSubview(cap)
            x += cap.frame.width + 6
        }
        let colunaTexto = L.pad + 122   // largura fixa da coluna de teclas: alinha as 4 linhas
        let nome = label(titulo, size: 12, weight: .semibold, color: PulsePalette.text)
        nome.frame = NSRect(x: colunaTexto, y: 17, width: 220, height: 16)
        linha.addSubview(nome)
        let desc = label(detalhe, size: 11, weight: .regular, color: PulsePalette.secondary)
        desc.frame = NSRect(x: colunaTexto, y: 2, width: width - colunaTexto - L.pad, height: 15)
        desc.autoresizingMask = [.width]
        linha.addSubview(desc)
        return linha
    }

    private func refreshPermissions() {
        guard permissoesArea != nil else { return }
        permissoesArea.subviews.forEach { $0.removeFromSuperview() }
        let itens: [(String, String, Bool, Bool, String)] = [
            ("Microfone", "para ouvir você",
             AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, false,
             "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
            ("Reconhecimento de fala", "transcreve dentro do seu Mac",
             SFSpeechRecognizer.authorizationStatus() == .authorized, false,
             "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"),
            ("Acessibilidade", "para escrever por você",
             AXIsProcessTrusted(), false,
             "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            ("Monitoramento de entrada", "pro duplo Option; sem ela, ⌥S",
             IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted, true,
             "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"),
        ]
        var y = permissoesArea.bounds.height
        for (nome, detalhe, concedida, opcional, url) in itens {
            y -= L.permH
            permissoesArea.addSubview(linhaPermissao(nome: nome, detalhe: detalhe, concedida: concedida,
                                                     opcional: opcional, url: url, y: y,
                                                     width: permissoesArea.bounds.width))
            y -= L.permGap
        }
    }

    private func linhaPermissao(nome: String, detalhe: String, concedida: Bool, opcional: Bool,
                                url: String, y: CGFloat, width: CGFloat) -> NSView {
        let linha = NSView(frame: NSRect(x: 0, y: y, width: width, height: L.permH))
        linha.autoresizingMask = [.width]
        let cor: NSColor = concedida ? .systemGreen : (opcional ? PulsePalette.muted : .systemPink)
        let ponto = NSView(frame: NSRect(x: L.pad, y: L.permH / 2 - 4, width: 8, height: 8))
        ponto.wantsLayer = true
        ponto.layer?.backgroundColor = cor.cgColor
        ponto.layer?.cornerRadius = 4
        linha.addSubview(ponto)
        let x = L.pad + 20
        let estado = concedida ? "Concedida" : (opcional ? "Opcional" : "Falta conceder")
        let nomeLabel = label(nome, size: 12, weight: .semibold, color: PulsePalette.text)
        nomeLabel.frame = NSRect(x: x, y: 22, width: 260, height: 16)
        linha.addSubview(nomeLabel)
        // `muted` da 3,07:1 sobre o fundo escuro, abaixo do minimo de 4,5:1 pra texto
        // normal. O tom fica so no ponto colorido; o texto usa secondary (6,17:1).
        let corTexto = (concedida || opcional) ? PulsePalette.secondary : cor
        let detalheLabel = label("\(detalhe) · \(estado)", size: 11, weight: .regular, color: corTexto)
        detalheLabel.frame = NSRect(x: x, y: 5, width: 320, height: 15)
        linha.addSubview(detalheLabel)
        if !concedida {
            let botao = NSButton(title: "Abrir ajustes", target: self, action: #selector(openSettingsPanel(_:)))
            botao.identifier = NSUserInterfaceItemIdentifier(url)
            botao.bezelStyle = .rounded
            botao.controlSize = .small
            botao.frame = NSRect(x: width - L.pad - 106, y: L.permH / 2 - 11, width: 106, height: 22)
            botao.autoresizingMask = [.minXMargin]
            linha.addSubview(botao)
        }
        return linha
    }

    private func blocoVocabulario(y: CGFloat, width: CGFloat) -> NSView {
        let bloco = NSView(frame: NSRect(x: 0, y: y, width: width, height: L.vocabH))
        bloco.autoresizingMask = [.width]
        let t = label("TERMOS EM INGLÊS", size: 10, weight: .bold, color: PulsePalette.secondary)
        t.frame = NSRect(x: L.pad, y: 24, width: 300, height: 14)
        bloco.addSubview(t)
        let d = label("Nome de cliente, jargão e termo em inglês que você usa no dia a dia.",
                      size: 11, weight: .regular, color: PulsePalette.secondary)
        d.frame = NSRect(x: L.pad, y: 5, width: width - L.pad - 160, height: 15)
        d.autoresizingMask = [.width]
        bloco.addSubview(d)
        let botao = NSButton(title: "Editar lista", target: self, action: #selector(abrirVocabulario))
        botao.bezelStyle = .rounded
        botao.controlSize = .small
        botao.frame = NSRect(x: width - L.pad - 106, y: 10, width: 106, height: 22)
        botao.autoresizingMask = [.minXMargin]
        bloco.addSubview(botao)
        return bloco
    }

    private func rodape(width: CGFloat) -> NSView {
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: width, height: L.footerH))
        footer.wantsLayer = true
        footer.autoresizingMask = [.width, .maxYMargin]
        let risco = NSView(frame: NSRect(x: 0, y: L.footerH - 1, width: width, height: 1))
        risco.wantsLayer = true
        risco.layer?.backgroundColor = PulsePalette.border.cgColor
        risco.autoresizingMask = [.width]
        footer.addSubview(risco)
        let mostrar = NSButton(checkboxWithTitle: "Mostrar esta tela ao abrir", target: self,
                               action: #selector(toggleShowOnLaunch))
        mostrar.state = (UserDefaults.standard.object(forKey: "PulseShowHelpOnLaunch") as? Bool ?? true) ? .on : .off
        mostrar.frame = NSRect(x: L.pad - 4, y: 18, width: 240, height: 20)
        footer.addSubview(mostrar)
        let entendi = NSButton(title: "Entendi", target: self, action: #selector(closeHelp))
        entendi.bezelStyle = .rounded
        entendi.keyEquivalent = "\r"
        entendi.bezelColor = PulsePalette.accent   // o azul padrao destoa da paleta do app
        entendi.frame = NSRect(x: width - L.pad - 92, y: 15, width: 92, height: 26)
        entendi.autoresizingMask = [.minXMargin]
        footer.addSubview(entendi)
        return footer
    }

    @objc private func abrirVocabulario() { NSWorkspace.shared.open(Vocabulario.arquivo) }
    @objc private func openSettingsPanel(_ sender: NSButton) {
        guard let string = sender.identifier?.rawValue, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func toggleShowOnLaunch(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "PulseShowHelpOnLaunch")
    }
    @objc private func closeHelp() { close() }
}

/// Tecla desenhada. Largura acompanha o texto: "Space" e "esc" sao mais largas que "S".
private final class KeyCapView: NSView {
    init(key: String) {
        let largura = max(30, CGFloat(key.count) * 8.5 + 20)
        super.init(frame: NSRect(x: 0, y: 0, width: largura, height: 24))
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 139 / 255.0, green: 35 / 255.0, blue: 229 / 255.0, alpha: 0.16).cgColor
        layer?.borderColor = NSColor(red: 139 / 255.0, green: 35 / 255.0, blue: 229 / 255.0, alpha: 0.4).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 5
        setAccessibilityElement(false)
        let texto = label(key, size: 11, weight: .medium, color: PulsePalette.text)
        texto.setAccessibilityElement(false)
        texto.alignment = .center
        texto.frame = NSRect(x: 0, y: 4, width: largura, height: 15)
        texto.autoresizingMask = [.width]
        addSubview(texto)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
private final class PulseWaveIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PulsePalette.accent.setStroke()
        let path = NSBezierPath(); path.lineWidth = 3; path.lineCapStyle = .round
        let middle = bounds.midY
        path.move(to: NSPoint(x: 2, y: middle)); path.line(to: NSPoint(x: 10, y: middle)); path.line(to: NSPoint(x: 15, y: middle + 12)); path.line(to: NSPoint(x: 21, y: middle - 15)); path.line(to: NSPoint(x: 27, y: middle + 8)); path.line(to: NSPoint(x: 33, y: middle)); path.line(to: NSPoint(x: 43, y: middle)); path.stroke()
    }
}
