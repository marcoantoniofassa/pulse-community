# Contribuir

Use macOS 26+, Apple Silicon, Swift 6.2+ e SDK macOS 26+. O app não precisa de pacotes externos de runtime.

```sh
git clone https://github.com/marcoantoniofassa/pulse-community.git
cd pulse-community
python3 tests/check_distribution.py
bash build.sh
```

O resultado fica em `dist/Pulse.app`. O build não instala nem abre o app. Por padrão usa assinatura ad-hoc; para uma identidade já configurada, defina `PULSE_SIGN_IDENTITY`. Não publique certificados ou credenciais. Builds diferentes podem exigir nova autorização de Acessibilidade/Monitoramento de Entrada.

`bash release.sh` gera DMG e checksums, sem sobrescrever DMG existente. A notarização só é tentada quando `PULSE_NOTARY_PROFILE` e uma identidade apropriada já estão configurados. Um build local não certifica notarização.

Para testar permissões e primeiro uso, prefira conta macOS de teste ou máquina separada. Não abra uma cópia de desenvolvimento sobre seus dados pessoais. Verifique três sessões consecutivas nos dois modos, cancelamento durante preparação/ditado, perda de foco, modelo indisponível e permissões negadas. Use dados sintéticos. Testes de distribuição não substituem esse roteiro.

Abra uma issue para discutir mudanças maiores; correções pequenas podem vir direto em PR. Descreva o problema, a mudança e o que foi realmente testado. Mantenha a captura de áudio sem bloqueio, o par novo SpeechTranscriber/Analyzer por sessão e a drenagem de resultados fora do MainActor. Não adicione telemetria nem conteúdo de fala aos logs.

Contribuições são recebidas sob MIT; só envie material que você tenha direito de licenciar. Vulnerabilidades seguem SECURITY.md.
