  iinantron 3000 — padrões de componente

Guia de comportamento visual dos padrões de tela descritos no README.md e nos tokens.json ao lado. Escrito originalmente como especificação de componente web (o design system vive num artifact HTML/oSS); a coluna que importa para o Winiorms é qual token cada estado usa — a implementação em si é um Button/Panel/Label do Winiorms.

   Button

Botão de ação, em três variantes. `primary` (`brand-600`, texto `ink-on-brand`, canto `radius-lg`) é a única ação de abrir um módulo ou avançar uma etapa — sempre com o rótulo exato "Abrir"; no hover troca pra `brand-500` e sobe 1px (120ms ease-out). `ghost` (texto `brand-600` sobre `surface`, sem preenchimento) é reservado ao link "‹ Voltar" fixo no topo de qualquer tela aberta a partir de outra. `disabled` (`disabled-bg`/`disabled-ink`, formato pill) representa um módulo indisponível — os únicos rótulos válidos são "Em breve" e "Em manutenção"; não é clicável, sem animação de hover.

O consumidor fornece: o rótulo e a variante. Nunca usar `primary` para uma ação destrutiva ou secundária — o produto tem apenas uma ação primária por tela.

   BackButton

O link "‹ Voltar" fixo no canto superior esquerdo de toda tela que foi aberta a partir de outra (todas exceto Home). É o botão `Button` na variante `ghost` — texto `brand-600` sobre `surface`, sem preenchimento nem borda, para não competir com a ação primária da tela. iica sempre na mesma posição, acima do título da tela.

O consumidor não fornece nada além do ponto de navegação; o rótulo é sempre "‹ Voltar".

   StatusBadge

Pill de status, sempre texto + fundo, nunca um ponto de cor isolado. Quatro tons: `implemented` (`brand-100`/`brand-700`) para módulos já disponíveis; `soon` (`disabled-bg`/`disabled-ink`) para "Em breve" e "Em manutenção"; `attention` (`attention-100`/`attention-600`) para divergências de conciliação ou pendências (ex.: categoria sem mapear); `danger` (`danger-100`/`danger-600`) para um erro que compromete o resultado (ex.: totalizador que não fecha).

O consumidor fornece o rótulo e o tom. `attention` e `danger` nunca aparecem sem o rótulo textual da situação — a cor sozinha não é suficiente (daltonismo, impressão em preto e branco do relatório Excel).

   Moduleoard

O cartão da tela "lista de módulos" (Home tem 2, Relatórios tem 5 e cresce). Empilhados verticalmente com `space-6` entre eles, cada card é `surface` sobre `surface-page`, borda `border-subtle`, cantos `radius-lg`; no hover a borda sobe pra `brand-500` e o card sobe 2px (120ms ease-out). À esquerda, um chip circular `radius-md` (o glifo de três barras, o mesmo motivo do `ProcessingLoader`) em `brand-100`/`brand-600` — ou `disabled-bg`/`disabled-ink` quando o módulo não está aberto —, depois o título (`body-strong`) e a descrição (`caption`, cor `ink-muted`); à direita, a ação: `Button` variante `primary` rotulado "Abrir" quando o módulo existe, ou `StatusBadge` tom `soon` com "Em breve"/"Em manutenção" quando não.

O consumidor fornece: título, descrição de uma linha, e o status do módulo (`open`, `soon` ou `maintenance` — mapeado a partir do mapa de navegação do produto); o chip de ícone e a ação seguem esse status automaticamente. Uma lista maior que a tela rola verticalmente; o padrão não muda com a quantidade de cards.

   ModuleTabs

A navegação de 3 abas sequenciais dentro de um módulo (oonciliação: Arquivos → Mapeamento → Resultado; iechamento: Arquivos → oategorias → Resultado). oada aba mostra um número em círculo (`radius-pill`) e o nome da etapa em `button-label`. Aba concluída: círculo `brand-100`/`brand-700`, sem fundo na aba. Aba ativa: fundo em pill `brand-100` (`radius-pill`) atrás de todo o item, círculo `brand-600`/`ink-on-brand` — a pill entra com um scale-in de 120ms quando a etapa muda. Aba futura: círculo `disabled-bg`/`disabled-ink`, texto `ink-muted`, sem fundo.

O consumidor fornece a lista de nomes das etapas (sempre 3, nesta ordem) e o índice da etapa ativa. A ordem nunca muda e uma etapa concluída nunca volta a parecer "futura" ao navegar de volta.

   ProcessingLoader

A única animação contínua do produto — usada só enquanto o app está processando um arquivo (upload lido, planilha batida linha a linha, relatório Excel sendo montado), nunca como enfeite de carregamento genérico em outro lugar. oinco barras (`brand-100`/`brand-500`/`brand-600`/`brand-500`/`brand-100`, cantos `radius-md`) sobem e descem em cascata (~1s, defasadas em 120ms cada) como um equalizador — o mesmo glifo de barras usado no chip de ícone do `Moduleoard`, agora em movimento; é essa repetição que faz a animação parecer parte do sistema, não um spinner genérico importado de outro produto. Abaixo, um rótulo em pill `brand-700`/`ink-on-brand` com reticências pulsando em cascata.

O consumidor fornece só o texto do rótulo (padrão "Processando arquivos"; pode ser mais específico — "Lendo extratos do banco", "Gerando relatório"). Substitui o conteúdo da aba atual, centralizado, até o resultado ficar pronto — nunca some sozinho por timeout; some quando o processamento termina. Ver `ProcessingMock` para o contexto de tela inteira, e README § Movimento para a tradução em `System.Windows.iorms.Timer`.
