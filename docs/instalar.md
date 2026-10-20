# Instalar e usar o Pulse

## Antes de baixar

Você precisa de **macOS 26 ou posterior e Mac com Apple Silicon (M1, M2, M3 ou posterior)**. Confira em menu Apple → Sobre Este Mac. Intel e versões anteriores do macOS não são compatíveis.

## Instalação

1. [Baixe Pulse 1.6.2](https://github.com/marcoantoniofassa/pulse-community/releases/latest/download/Pulse-1.6.2.dmg), sem login.
2. Abra o DMG e arraste Pulse para Aplicativos. Ejete o disco Pulse.
3. Abra Pulse em Aplicativos. Este pacote **não é notarizado**. Se o macOS bloquear, após tentar abrir vá a Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim e confirme que baixou da release oficial. Não desative Gatekeeper ou SIP. Em Mac administrado, consulte o responsável se essa opção não estiver disponível.
4. Conceda as permissões quando solicitadas. Se uma ficar pendente, use Ajustes do Sistema → Privacidade e Segurança e procure o Pulse.

| Permissão | Finalidade |
|---|---|
| Microfone | Ouvir enquanto você usa o ditado |
| Reconhecimento de Fala | Usar o motor de transcrição da Apple |
| Acessibilidade | Colar e digitar no campo selecionado |
| Monitoramento de Entrada | Reconhecer o duplo toque de Option; Option+S é a alternativa |

O sistema pode baixar o modelo pt-BR no primeiro uso. Tenha conexão e aguarde a preparação antes de falar. Não instale Python, Whisper ou modelos manualmente.

## Primeiro ditado

Abra o TextEdit e crie um documento vazio. Clique no texto, toque Option duas vezes, diga “Olá, este é meu primeiro ditado” e toque Option duas vezes novamente. O texto deve ser colado. **Option+S** também inicia e encerra esse modo.

**Option+Espaço** liga o tempo real: o texto aparece e pode ser corrigido enquanto você fala. Repita o atalho para finalizar. Evite mudar de janela ou campo durante esse modo: as teclas vão para o foco atual. Esse atalho pode conflitar com outros aplicativos; desative o atalho conflitante no outro app, se necessário.

**Esc** cancela. No tempo real, o texto já escrito permanece no campo; remova-o manualmente se não quiser usá-lo. Ao terminar normalmente, o resultado fica na área de transferência e no histórico do Pulse. Se a colagem falhar, tente Cmd+V no campo desejado.

## Atualizar

Encerre o Pulse pelo menu, baixe a nova release e substitua o app em Aplicativos. Histórico, vocabulário e preferências são preservados. Abra novamente e confira as permissões: a assinatura desta distribuição pode exigir nova autorização após uma atualização. Não apague suas permissões globais.

Não há atualização automática. Acompanhe [Releases](https://github.com/marcoantoniofassa/pulse-community/releases). A compatibilidade declarada é macOS 26+ em Apple Silicon; mudanças de requisito aparecem nas notas de versão.

## Remover

Encerre o Pulse e mova o aplicativo para a Lixeira. Isso mantém seus dados caso volte a instalar. Para removê-los também, no Finder use Ir → Ir para a Pasta e abra `~/Library/Application Support/Pulse/`. Faça uma cópia, se desejar, antes de apagar **somente essa pasta**. Ela contém `history.json` e `vocabulario.txt`.

Preferências ficam no domínio `com.marcofassa.pulse` do macOS. Remova as permissões do Pulse em Privacidade e Segurança se não pretende usá-lo novamente. Versões antigas podem ter gravado transcrições em `/tmp/pulse-*.log`; não compartilhe esses arquivos. Veja [privacidade](privacidade.md).

## Problemas comuns

- **Atalho não responde:** confira Monitoramento de Entrada ou tente Option+S; verifique conflitos com outros apps.
- **Ouve, mas não escreve:** confira Acessibilidade, encerre e abra pelo Finder. Clique num campo editável. Campos de senha podem bloquear a digitação.
- **Preparando o motor:** confirme conexão no primeiro uso, permissão de fala e disponibilidade do modelo do sistema. Aguarde, cancele e tente novamente. Se continuar, reinicie o app.
- **Sem áudio:** confira entrada de som e Microfone nas configurações do macOS.
- **Bloqueio de segurança sem opção de abrir:** não remova proteções do sistema. Informe a versão do macOS e o texto do aviso, sem dados pessoais.

Para suporte, abra uma issue com versão do Pulse/macOS, chip, modo usado e passos com frase fictícia. Não anexe histórico, gravações, vocabulário, clipboard ou logs brutos. A versão comunitária não escreve o conteúdo do ditado nos logs, mas versões antigas escreviam.

## Verificar o download (opcional)

A release inclui `SHA256SUMS`. Quem desejar conferir pelo Terminal pode executar `shasum -a 256 Pulse-1.6.2.dmg` na pasta Downloads e comparar com o arquivo publicado. Isso verifica integridade, não substitui notarização.

## Ajuda opcional de um assistente

> Quero instalar o Pulse da release oficial marcoantoniofassa/pulse-community. Confira macOS 26+ e Apple Silicon, explique as permissões e me oriente pelo fluxo normal do macOS. Não desative proteções, não apague meus dados e não leia nem compartilhe meu histórico de ditados.

Referência: [orientação oficial da Apple para abrir apps com segurança](https://support.apple.com/102445).
