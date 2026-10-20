# Privacidade

O Pulse usa SpeechAnalyzer/SpeechTranscriber da Apple, em pt-BR no aparelho. Não implementa conta, analytics, telemetria ou envio do áudio a um servidor do Pulse. O macOS pode usar internet para obter os modelos e recursos do sistema; “local” não significa que o computador nunca usa internet.

- Histórico: texto, data, duração e nome do aplicativo em `~/Library/Application Support/Pulse/history.json`. Entradas anteriores a 72 horas são removidas ao carregar e salvar o histórico, não por um serviço permanente.
- Vocabulário: `vocabulario.txt` na mesma pasta. Pode conter termos pessoais; não o anexe ao suporte.
- Clipboard: o ditado concluído substitui o conteúdo da área de transferência. Outros apps com acesso ao clipboard podem lê-lo.
- Diagnóstico: esta edição remove texto, caracteres ditados, conteúdo do clipboard e nome do app de destino dos logs de transcrição/colagem. Há diagnósticos técnicos locais em `/tmp/pulse-transcriber.log`, `/tmp/pulse-paste.log` e `/tmp/pulse-keystroke.log`. Erros do sistema podem conter caminhos locais. Não envie arquivos brutos.
- Áudio: no caminho nativo, os buffers seguem ao motor em memória. O código legado ainda pode criar arquivos WAV temporários vazios; versões anteriores podem ter deixado gravações no diretório temporário do usuário. Esta atualização não apaga arquivos pessoais preexistentes.

O histórico é um arquivo local sem criptografia própria; a proteção depende da conta e do armazenamento do macOS. Use frases fictícias para reproduzir problemas. Para apagar os dados, siga o guia de instalação.
