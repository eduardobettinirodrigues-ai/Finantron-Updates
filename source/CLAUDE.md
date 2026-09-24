# Concilia — como trabalhar neste projeto

## Fluxo de melhorias (leia antes de mexer em código)

Não há git neste projeto: o código-fonte compartilhado vive na pasta `source/` do repositório de atualizações (`Finantron-Updates`), e todo mundo que tem o `github_token.txt` ao lado do `App.ps1` pode baixar e publicar. Quem pedir uma melhoria ao Claude Code deve seguir este roteiro (o Claude executa tudo, não precisa pedir confirmação de cada passo):

1. **Antes de começar, sincronize:** `powershell -File ConciliacaoApp\sync-source.ps1` — baixa o código mais recente publicado e sobrescreve os arquivos locais. Sem isso você pode desfazer o trabalho de outra pessoa.
2. Faça a mudança. **Suba a versão** em `$Script:AppVersion` no `ConciliacaoApp/App.ps1` (patch `1.5.1` pra correção, minor `1.6.0` pra novidade). O `publish-update.ps1` recusa versão que não seja maior que a publicada.
3. Teste antes de publicar: dot-source do `App.ps1` chamando as funções direto (caminhos que só existem via clique também! ver lições abaixo), `test-run.ps1` (usa as planilhas de teste da pasta; o resultado de referência é `Saldo original total: 931.11 | Saldo ajustado total: 930.11`), e renderizar a tela com `Form.DrawToBitmap` em DPI 144 quando mexer em layout.
4. Gere: `build.ps1` e depois `build-installer.ps1`, e publique: `publish-update.ps1 -Versao "x.y.z" -Notas "texto que o usuário vai ler"`. Isso envia instalador + `version.json` e atualiza o `source/` (só os arquivos que mudaram). Os apps instalados avisam da nova versão sozinhos em alguns minutos (o CDN do GitHub atrasa; confirme pela API, não pelo raw).
5. Como o erro de uma versão chega a todos os PCs, o passo 3 não é opcional. Se publicou algo quebrado, publique a correção com versão maior o quanto antes.

Nomes internos que **não** devem ser renomeados (quebram quem já tem o app instalado): a pasta de instalação `%LOCALAPPDATA%\ConciliacaoVendas` (guarda `config.json`), o repositório `Finantron-Updates` e o arquivo `ConciliacaoVendas_Instalador.exe` dentro dele (URL gravada nos apps até a 1.4.5).

Build local: `ConciliacaoApp/build.ps1` (precisa do módulo `ps2exe`: `Install-Module ps2exe -Scope CurrentUser`), depois `build-installer.ps1`. Publicar manualmente continua possível com `publish-update.ps1` + `github_token.txt`, mas o caminho normal é o CI.

## Lições técnicas (PowerShell 5.1 + WinForms + Excel COM)

- **Closure:** nunca leia `$Script:` direto dentro de `.GetNewClosure()` em evento assíncrono (Paint, DrawItem…); copie pra variável local antes. Chamar função pelo nome dentro do closure é seguro.
- **Evento de descarte:** só existe `Disposed` (`Add_Disposed`); `Add_Disposing` estoura na criação do controle. Caminhos que só rodam por clique (ex.: o loader de "Analisar") precisam ser executados uma vez por dot-source, não só revisados no olho.
- **Cantos arredondados:** `Region` não tem antialiasing (serrilha). Pinte à mão no `Paint` (fundo do pai → `FillPath` antialiased → texto) e controle hover/press manualmente. Um helper de canto deve aplicar o efeito na hora *e* no `Resize`, não só no Resize.
- **DPI:** o processo é DPI-aware (`SetProcessDpiAwarenessContext(-3)`) com `AutoScaleMode=None`; a 125%/150% as fontes crescem mas pixels fixos não. Derive geometria de métricas de fonte (`Font.Height`, `GetPreferredSize`, `TextRenderer.MeasureText`), não de números fixos. Filhos de `GroupBox` começam no topo da caixa: comece em `DisplayRectangle.Top`. `Label` com `AutoSize=$true` ignora `.Size`; texto que quebra linha precisa de `AutoSize=$false`.
- **AutoScroll + Anchor:** não ancore `Right` um filho direto de painel `AutoScroll` (loop de crescimento); use um painel intermediário sem AutoScroll com largura sincronizada no `Resize`. O gap do `Anchor` é capturado quando o controle é parentado — o pai já precisa estar com o tamanho real nessa hora.
- **Dock:** o último controle adicionado com `Dock=Top` fica mais no topo; o `Fill` entra primeiro.
- **Excel COM:** nunca escreva escalar com `.Value2 = x` numa célula (quebra uma escrita em bloco não relacionada depois); use `$ws.Cells.Item(r, c) = x` e pegue o Range separado, se precisar estilizar. Escrita em bloco (`Range.Value2 = $array2D`) é ok. Abrir pasta protegida com senha errada trava o Excel num diálogo invisível: valide a senha antes.
- **Testar UI:** a janela DPI-aware exige que o PowerShell que faz `GetWindowRect`/`MoveWindow`/`CopyFromScreen` também seja DPI-aware, senão as medidas vêm erradas sem erro nenhum.
- **Publicação:** `raw.githubusercontent.com` serve `version.json` velho por alguns minutos (query de cache-busting não resolve); confirme a publicação pela API de conteúdo do GitHub.

# Concilia — identidade visual

O app (antes "Finantron 3000"; agora **Concilia**) (`ConciliacaoApp/App.ps1`, PowerShell + System.Windows.Forms nativo, gerando `Concilia.exe`) está migrando de telas WinForms sem paleta própria pra uma identidade branca e em tons de verde, com layout reformulado (cantos maiores, topo sem barra cheia, uma animação de carregamento própria). Ao tocar em qualquer código de UI dentro de `ConciliacaoApp/`, aplique o design system descrito em `design-system/`:

- `design-system/README.md` — o brand book: regras de cor, tipografia, espaçamento, movimento/animação, os padrões de tela (topo, lista de módulos, 3 abas, botão Voltar, tela de processamento, pills de status) e o padrão proposto para os relatórios Excel.
- `design-system/tokens.json` — os valores exatos (hex de cor, tamanhos de fonte, espaçamento em px, raio de canto) com uma nota de uso por token.
- `design-system/components.md` — como cada padrão de tela (botão, card de módulo, abas, badge de status, loader de processamento) usa esses tokens.

## O que mudou nesta versão

- `radius-lg` (16px) é o canto padrão agora em cards, botões e no card do loader — maior que o antigo `radius-md`/8px.
- O topo da tela não usa mais um preenchimento sólido (`brand-700`) de ponta a ponta: é o ícone do app + nome direto sobre o fundo, com uma régua verde de 3px embaixo. `brand-700` sobrou só pra chips de alta ênfase.
- Cada card de módulo ganhou um chip circular com um glifo de três barras (ícone de sistema pra "módulo"/"dado financeiro").
- A aba ativa dos módulos usa um fundo em pill (`brand-100`), não só um sublinhado.
- Nova animação: `ProcessingLoader` — cinco barras em cascata, a única animação contínua do produto, usada só enquanto o app está lendo/gerando um arquivo.

## O logo e o ícone

O logo é o **"Livro C"** (opção 1a do handoff de design "Financial app logo design"): um C montado com 5 linhas de lançamento e um visto de conciliado no vão. Ele é desenhado em código (`New-ConciliaLogoBitmap` em `App.ps1`, geometria do SVG original em viewBox 48×48) e tem duas versões: **Glifo** (barras `#0F3D25` + visto `#1A8A4A`, sem fundo, usado no topo das telas a ~40px ao lado do nome "Concilia") e **Tile** (quadrado `#1A8A4A`, barras brancas + visto `#0F3D25`, usado no ícone da janela e no `app.ico`). `ConciliacaoApp/app.ico` é gerado por `make-icon.ps1` a partir do Tile — rode-o de novo só se o logo mudar; não edite o `.ico` na mão. O antigo mascote ("dinheiro com olhos") foi aposentado.

## Traduzindo os tokens pra WinForms

- Cor: `#RRGGBB` de `tokens.json` → `Color.FromArgb(...)` (ou `ColorTranslator.FromHtml("#RRGGBB")`).
- Tipografia: uma família só, Segoe UI — já é a fonte padrão do Windows, não precisa instalar nada; só ajustar tamanho/peso por controle conforme os estilos de `tokens.json` (`title-app`, `title-module`, `body-strong` etc.).
- Espaçamento (`space-*`): padding/margin dos controles, em pixels, nos valores exatos do token.
- Raio (`radius-*`): WinForms não tem `border-radius` nativo — cantos arredondados exigem `GraphicsPath`/`Region` customizados (ou `FlatStyle.Flat` com painel próprio). Onde não vale o esforço, prefira manter cantos retos a aproximar um raio errado.
- "Bordas, não sombra" é uma regra do brand: cards usam `Panel` com `BorderStyle`/desenho de borda (`border-subtle`, sobe pra `brand-500` no hover), nunca `DropShadow` ou efeito de sombra.
- `ProcessingLoader`: uma `UserControl` com `System.Windows.Forms.Timer` (~60ms de tick) redesenhando 5 retângulos cuja altura segue uma função periódica (seno/triangular) defasada por barra — mesmo efeito do `@keyframes` CSS do design system, calculado a cada tick. Mostra só enquanto o app está processando um arquivo; nunca como spinner genérico em outro lugar.

## Fonte deste design system

Foi gerado a partir de `Finantron3000_Escopo_Design.md` (na pasta acima) e vive como um Design System artifact no Cowork — se o escopo mudar ou surgirem novos módulos (Fluxo de Caixa, Contas a Receber, Indicadores Financeiros), atualize os tokens lá e re-exporte esta pasta, em vez de editar valores direto no código sem registrar a mudança aqui. Há também uma apresentação em slides desse redesign, se você precisar mostrar a identidade nova pra alguém antes de aplicar no código.
