## Sobre o produto

Concilia (antes "Finantron 3000") é um aplicativo desktop Windows (`.exe`, WinForms) de uso interno para uma rede de padarias/restaurantes com duas unidades — Mooca e Vila Moura. Hoje resolve conciliação de vendas e fechamento de contas a pagar/DRE; é um hub que vai crescer com novos módulos financeiros. Quem usa é operação, não gente técnica — a interface precisa ser óbvia sem manual, e o entregável final de cada módulo é sempre um relatório Excel, que é tão "produto" quanto a tela.

Este design system parte do zero de identidade: o app roda em telas nativas do Windows sem paleta própria (cabeçalhos cinza `#1F1F1F`/`#3D3D3D`, cards brancos com borda simples). A direção é branca e em tons de verde, construída para ser aplicada tanto nas telas WinForms quanto nos relatórios Excel.

## Reformulação de layout

A v1 deste sistema recolorou o cabeçalho escuro de cinza pra verde (`brand-700`), mantendo a estrutura antiga. Esta versão vai além: menos preenchimento sólido, mais espaço em branco, cantos mais soltos e uma única animação de destaque no lugar certo.

- **`brand-700` deixou de ser uma barra cheia.** A tela agora é branca/`surface-page` do topo ao fim; `brand-700` sobra só pra chips de alta ênfase (o rótulo do loader, o item de navegação ativo).   topo da tela é o logo do Concilia (glifo "Livro C") + `title-app` direto sobre `surface-page`, com uma régua de `space-1` em `brand-600` sob o nome — a marca aparece sem precisar de um bloco escuro carregando a tela.
- **Cantos maiores.** Cards de módulo, botões e o card do loader usam `radius-lg` (16px, era `radius-md`/8px) — o principal sinal de "versão nova" ao lado da paleta. `radius-md` sobra pra chrome pequeno (chip de ícone, painel de aba); `radius-sm` continua nos campos de formulário.
- **Ícone em cada card de módulo.** Um chip circular `brand-100`/`brand-600` com o glifo de barras (o mesmo motivo do loader — ver Movimento) antes do título, pra dar identidade visual mesmo numa lista de texto.
- **Abas em pill.** A aba ativa ganha fundo `brand-100` arredondado (`radius-pill`) em vez de só um sublinhado — mais fácil de ver à distância, mesmo padrão visual dos badges de status.
- Ver `HomeMock` e `ProcessingMock` pra a composição inteira; os componentes atômicos (`Button`, `ModuleCard`, `ModuleTabs`, `StatusBadge`, `BackButton`, `ProcessingLoader`) documentam cada peça isolada.

## Fundamentos de conteúdo

- Português do Brasil, direto, sem jargão financeiro não explicado — quem lê é a operação da padaria, não um contador.
- Rótulos de estado são exatamente estes três, sempre nesta forma: "Abrir", "Em breve", "Em manutenção" — nunca sinônimos ("Disponível em breve", "Indisponível").
- Sem emoji na interface.   mapa de navegação do escopo original usa ✅/⏳ só como anotação de planejamento, não como padrão visual.
- Nomes de tela seguem o mapa de navegação: Home, Movimentações, Relatórios, Conciliação de Vendas, Fechamento CP e DRE.

## Fundamentos visuais

- **Cor.** `surface-page` é o fundo da janela inteira, do topo ao fim. `surface` é usado em cards, painéis e no conteúdo das abas.   verde é a cor de marca: `brand-600` é a cor de ação — botão primário "Abrir", pill da aba ativa, links, o glifo do ícone de módulo; `brand-700` é reservado a chips de alta ênfase (rótulo do loader, item de navegação selecionado); `brand-100` marca seleção e é o fundo do chip de ícone e do pill "Implementado". `ink` é o texto padrão, `ink-muted` é texto secundário. `attention-600`/`attention-100` e `danger-600`/`danger-100` são os únicos tons fora do branco-e-verde, reservados a divergência e a erro crítico — nunca decorativos, sempre acompanhados da palavra ("Divergência", "Não bate"), nunca só a cor.
- **Tipografia.** Uma família só, `sans` (Segoe UI, a fonte nativa do Windows — sem arquivo pra embutir, o sistema operacional já a fornece). `title-app` é o nome do produto ao lado do ícone; `title-module` nomeia a tela; `title-section` nomeia cada uma das 3 abas de um módulo; `body-strong`/`body` são o padrão de card e tabela; `caption` é a linha de descrição e o texto do loader; `button-label` é o texto de botões, pills e abas.
- **Espaçamento e cantos.** `radius-lg` em cards, botões e no card do loader; `radius-md` no chip de ícone e no painel de conteúdo da aba; `radius-pill` em badges, no indicador de etapa e na pill da aba ativa; `radius-sm` em campos de formulário. `space-4` é o padding padrão de card; `space-6` separa os cards empilhados e afasta o ícone do nome no topo; `space-8` é a margem da tela.
- **Bordas, não sombra.** Cards são delimitados por `border-subtle` (e sobem pra `brand-500` no hover — ver Movimento), nunca por `box-shadow`. `border-strong` é reservado ao contorno de campos de formulário.
- **Estado desabilitado.** "Em breve" e "Em manutenção" usam `disabled-bg`/`disabled-ink` — cinza neutro, nunca uma variação de verde (verde sempre significa "disponível/ativo" no produto).

## Movimento

Poucas animações, sempre com propósito — nunca decoração. Duas famílias:

- **Feedback de interação** (rápido, ~120ms, ease-out): hover de um card sobe a borda de `border-subtle` pra `brand-500` e o card sobe 2px; hover do botão primário troca `brand-600` → `brand-500`; a pill da aba ativa e o pill "Implementado" entram com um leve scale-in (0.92 → 1) quando aparecem, nunca em loop.
- **A animação especial: `ProcessingLoader`.** É o único momento do produto com uma animação contínua, e é proposital — é o retrato visual de "o app está batendo suas planilhas linha a linha". Quatro barras na cor `brand-600`/`brand-500`/`brand-100` (o mesmo glifo do ícone de módulo) sobem e descem em cascata, ritmo ~1s, como um equalizador — a mesma metáfora usada no ícone de cada card de módulo, agora em movimento. Aparece sempre que o app está processando arquivos (upload, leitura da planilha, geração do Excel), nunca como enfeite de carregamento genérico. Ver `ProcessingLoader` e `ProcessingMock`.
- **Tradução pra WinForms.** WinForms não tem transição de CSS; two caminhos: (1) estados discretos — recolorir no `MouseEnter`/`MouseLeave`, sem interpolação, pra hover de botão e card; (2) para o loader, uma `UserControl` com `System.Windows.Forms.Timer` (~60ms de tick) redesenhando N retângulos com altura de uma função periódica (seno ou triangular) defasada por barra — o mesmo efeito do CSS `@keyframes`, calculado a cada tick em vez de interpolado pelo navegador.

## Padrões de tela

- **Topo.** Ícone do app (ver Iconografia) + `title-app`, direto sobre `surface-page`, régua `brand-600` sob o nome. Sem barra escura cheia.
- **Lista de módulos** (Home, Relatórios): cards empilhados verticalmente (`space-6` entre eles), cada um com o chip de ícone, `body-strong` no título, `caption` na descrição, e a ação à direita — "Abrir" (`Button` primary) quando o módulo existe, pill `disabled` com "Em breve" ou "Em manutenção" quando não. Ver `ModuleCard`.
- **Módulo com 3 abas** (Conciliação, Fechamento): sempre a mesma sequência — Arquivos → Mapeamento/Categorias → Resultado. A aba ativa ganha a pill `brand-100`/`brand-700`; abas concluídas mostram o mesmo tratamento mais claro pra indicar progresso, nunca voltam a parecer "não visitadas". Ver `ModuleTabs`.
- **Botão Voltar.** Toda tela aberta a partir de outra tem "‹ Voltar" fixo no topo, como link, não como botão preenchido. Ver `BackButton`.
- **Processando.** Ao confirmar upload/gerar relatório, o conteúdo da aba é substituído pelo `ProcessingLoader`, centralizado, até o resultado ficar pronto. Ver `ProcessingMock`.
- **Indicadores de status.** "Implementado" (`brand-100`/`brand-700`), "Em breve"/"Em manutenção" (`disabled-bg`/`disabled-ink`), "Divergência" (`attention-100`/`attention-600`) e "Não bate" (`danger-100`/`danger-600`) são sempre um pill com texto — nunca um ponto de cor isolado. Ver `StatusBadge`.

## Relatórios Excel

 s relatórios (aba "Capa" + abas de detalhamento) são o que a operação realmente olha no dia a dia — merecem o mesmo sistema, não uma paleta ad-hoc por aba:

- Cabeçalho de tabela: fundo `brand-700`, texto branco (`ink-on-brand`) — aqui, ao contrário da tela, um preenchimento sólido continua correto: é uma grade densa de dados, não uma janela de app.
- Linhas de dado alternam `surface`/`surface-sunken`; a linha de total usa `brand-100` com texto em `brand-700` (`body-strong`).
- Coluna de diferença banco vs. sistema: valor zerado em `ink` normal; divergência em `attention-100` de fundo com texto `attention-600`; uma diferença que indica erro grave (ex.: totalizador não fecha) em `danger-100`/`danger-600`. Sempre com um rótulo textual (" K", "Divergência", "Não bate"), nunca só a cor da célula.
- Checks de validação (aba de checks do Fechamento): mesmo par `attention`/`danger` para "tem categoria sem mapear?" e "bate com o total?".

## Iconografia

  mascote — "dinheiro com olhos" (maço de notas verde, tarja vermelha, olhos grandes) — está registrado em `assets/Mascote`, arquivo original do usuário. Uso: o ícone do app (barra de título, atalho, instalador) e, pequeno (~40px), ao lado de `title-app` no topo de cada tela — nunca redesenhado, redimensionado sem manter proporção, ou recolorido. Dentro das telas, o glifo de barras (três retas verticais de altura crescente, `brand-600`) é o ícone de sistema pra "módulo"/"dado financeiro" — usado no chip de cada `ModuleCard` e nas barras do `ProcessingLoader`; é dele, não do mascote, que vem a repetição visual. Ícones lineares simples de um traço só (seta do Voltar, check, upload) seguem em `ink-muted` ou `brand-600`.
