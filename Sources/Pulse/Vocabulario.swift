import Foundation

/// Vocabulario contextual: termos que o motor de fala passa a ESPERAR dentro da
/// fala em portugues.
///
/// O SpeechAnalyzer trabalha com UM locale por sessao: nao existe "segundo
/// idioma". O que existe e `AnalysisContext.contextualStrings`, que aumenta a
/// probabilidade de certas palavras serem reconhecidas. E isso que faz
/// "pull request", "deploy" e "endpoint" sairem certos no meio de uma frase em
/// portugues, em vez de virarem aproximacoes foneticas.
///
/// A lista do usuario vive em texto puro, uma expressao por linha, em
/// ~/Library/Application Support/Pulse/vocabulario.txt. Na primeira execucao o
/// arquivo nasce com os termos padrao, entao editar e so abrir e escrever.
enum Vocabulario {

    /// Teto defensivo. A Apple nao documenta um limite para contextualStrings, e
    /// lista gigante tende a diluir o efeito de cada termo em vez de somar.
    /// ponytail: numero escolhido por prudencia, subir so com medicao.
    private static let teto = 500

    static var arquivo: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vocabulario.txt")
    }

    /// Termos padrao: ingles tecnico e de gestao que aparece no portugues falado
    /// do dia a dia, mais nomes proprios de ferramenta que o motor nao conhece.
    static let padrao: [String] = [
        // engenharia
        "deploy", "commit", "branch", "merge", "pull request", "code review", "rollback",
        "endpoint", "backend", "frontend", "front-end", "back-end", "full-stack",
        "feature", "bug", "hotfix", "release", "build", "script", "token", "webhook",
        "API", "framework", "log", "cache", "migration", "query", "database",
        "container", "cluster", "timeout", "callback", "thread", "worker", "cron",
        "staging", "hardcoded", "refactor", "boilerplate", "deploy automatico",
        "open source", "repositorio", "merge request", "issue", "milestone",
        "pipeline", "runtime", "output", "input", "parser", "payload", "header",
        // IA
        "prompt", "embedding", "fine-tuning", "LLM", "agente", "workflow", "skill",
        "context", "hook", "subagente", "modelo", "inferencia", "streaming",
        // gestao e negocio
        "kanban", "board", "sprint", "backlog", "call", "meeting", "follow-up",
        "one-on-one", "lead", "churn", "onboarding", "budget", "insight",
        "benchmark", "roadmap", "stakeholder", "turnover", "headcount", "upsell",
        "trial", "SLA", "KPI", "NPS", "MVP", "deadline", "kickoff", "review",
        "briefing", "feedback", "handoff", "checkpoint", "status report",
        // ferramentas
        "GitHub", "Supabase", "Railway", "Cloudflare", "Chatwoot", "Pipedrive",
        "Notion", "Slack", "Discord", "WhatsApp", "Claude", "Codex", "n8n",
        "Docker", "Swift", "Python", "TypeScript", "React", "Next.js", "Figma",
        "Postgres", "Redis", "Evolution API", "Asana", "Obsidian", "Xcode",
        // aplicativo
        "Pulse",
    ]

    /// Le a lista do usuario. Cria o arquivo com os termos padrao na primeira vez.
    /// Linha vazia e linha comecando com # sao ignoradas.
    static func carregar() -> [String] {
        let url = arquivo
        if !FileManager.default.fileExists(atPath: url.path) {
            let cabecalho = """
            # Vocabulario do Pulse
            #
            # Uma expressao por linha. Sao os termos que o Pulse passa a esperar
            # dentro da sua fala em portugues, entao ponha aqui o ingles tecnico
            # que voce usa, nome de cliente, de produto e de pessoa.
            #
            # Linha vazia e linha com # sao ignoradas. Vale ate \(teto) termos.
            # Salve o arquivo: o proximo ditado ja usa a lista nova.

            """
            try? (cabecalho + padrao.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return padrao
        }
        let texto: String
        do {
            texto = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Cair no padrao calado faz o log mentir ("133 termos") quando a lista do
            // usuario foi inteiramente ignorada. Melhor dizer.
            NSLog("Pulse: nao consegui ler vocabulario.txt (\(error)), usando a lista padrao")
            return padrao
        }
        // components(separatedBy: .newlines) cobre \n, \r\n e \r. Com split(separator:
        // "\n") um arquivo salvo em CRLF vira UM termo gigante e a feature morre calada.
        let termos = texto
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return Array(termos.prefix(teto))
    }
}
