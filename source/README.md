# Concilia

App desktop Windows (PowerShell 5.1 + WinForms, compilado em `Concilia.exe` com ps2exe) para conciliação de vendas (Mooca / Vila Moura × C6 / Sicredi) e fechamento de contas a pagar / DRE. Os relatórios finais saem em Excel.

## Melhorar o app com o Claude Code (passo a passo)

1. Descompacte a pasta em qualquer lugar (ex.: `C:\Concilia`). Ela já traz o `github_token.txt` em `ConciliacaoApp\` — é ele que dá permissão de publicar.
2. Instale o [Claude Code](https://claude.com/claude-code) e, num PowerShell, o compilador: `Install-Module ps2exe -Scope CurrentUser`. Precisa também de Excel instalado (o app lê/gera planilhas por COM).
3. Abra o Claude Code dentro da pasta descompactada (`cd C:\Concilia` e `claude`). Ele lê o `CLAUDE.md` sozinho: regras de design, lições técnicas e o roteiro de publicação.
4. **Primeiro comando, sempre:** `powershell -File ConciliacaoApp\sync-source.ps1` (o Claude faz isso sozinho seguindo o `CLAUDE.md`) — puxa o código mais recente que alguém já publicou.
5. Peça a melhoria em português ("adiciona X na tela Y", "corrige Z"). O Claude altera, testa, sobe a versão, gera o build e publica. Os PCs com o app instalado avisam da nova versão em alguns minutos — ninguém reinstala.

## Como o código fica em sincronia entre as pessoas

Não usamos git. A cada publicação, o `publish-update.ps1` envia o código (`App.ps1`, scripts, design system, docs) para a pasta `source/` do repositório `Finantron-Updates`, e o `sync-source.ps1` baixa de lá. Regra de ouro: **sincronizar antes de mexer, publicar logo depois de testar**. O publish recusa uma versão que não seja maior que a já publicada, então uma cópia desatualizada não consegue sobrescrever a de outra pessoa.
