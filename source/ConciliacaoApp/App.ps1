#requires -Version 5.1
# Concilia (ex Finantron 3000 / Conciliacao de Vendas) - Mooca / Vila Moura x C6 / Sicredi

# DPI awareness: sem isso, o Windows faz "DPI virtualization" (redimensiona a janela inteira
# via bitmap stretch) em qualquer monitor com escala != 100% - deixa tudo borrado, texto,
# icones, os cantos arredondados. As telas do app usam AutoScaleMode=None e matematica de
# pixel fixo de proposito (ver notas em New-ConciliacaoPanel), entao o certo e pedir ao Windows
# pra nao escalar a janela via bitmap e deixar renderizar nativo no DPI do sistema - fica menor
# em telas de alta densidade, mas nitido, coerente com o layout ja ser pixel-fixo. Precisa
# rodar ANTES de qualquer Form ser criado; falha silenciosa (Windows antigo sem a API) porque
# o app ja funcionava sem isso, so borrado - nunca deve travar por causa disso.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DSDpiAwareness {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
    $dpiAwarenessSystemAware = [IntPtr](-3)
    if (-not [DSDpiAwareness]::SetProcessDpiAwarenessContext($dpiAwarenessSystemAware)) {
        [DSDpiAwareness]::SetProcessDPIAware() | Out-Null
    }
} catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================================
# DESIGN SYSTEM (ver design-system/README.md, tokens.json, components.md na raiz do
# projeto). Fonte unica de verdade pra cor/tipografia/espacamento - se o token mudar la,
# muda aqui, nao direto nos controles espalhados pelo arquivo.
# ============================================================================
function DSColor([string]$Hex) { [System.Drawing.ColorTranslator]::FromHtml($Hex) }

$Script:DS = [PSCustomObject]@{
    SurfacePage   = DSColor "#F6FAF7"
    Surface       = DSColor "#FFFFFF"
    SurfaceSunken = DSColor "#EEF5F0"
    BorderSubtle  = DSColor "#D7E4DA"
    BorderStrong  = DSColor "#B7CCBD"
    Ink           = DSColor "#142A20"
    InkMuted      = DSColor "#5B6D62"
    InkOnBrand    = DSColor "#FFFFFF"
    Brand700      = DSColor "#143D2B"
    Brand600      = DSColor "#1E7A48"
    Brand500      = DSColor "#2C9159"
    Brand100      = DSColor "#E3F2E8"
    DisabledBg    = DSColor "#E7EAE7"
    DisabledInk   = DSColor "#7C867E"
    Attention600  = DSColor "#8A5A00"
    Attention100  = DSColor "#FBF0DC"
    Danger600     = DSColor "#A32B1F"
    Danger100     = DSColor "#FBE4E1"
}

# tokens.json da o tamanho em px (web); WinForms usa pontos a 96dpi (AutoScaleMode=None
# nas telas do app, entao 1pt = 1.333px vale sem surpresa) - px/1.333 convertido abaixo.
function DSFont([string]$Estilo) {
    switch ($Estilo) {
        "title-app"     { return New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold) }      # 32px
        "title-module"  { return New-Object System.Drawing.Font("Segoe UI", 16.5, [System.Drawing.FontStyle]::Bold) }   # 22px
        "title-section" { return New-Object System.Drawing.Font("Segoe UI", 12.75, [System.Drawing.FontStyle]::Bold) }  # 17px
        "body-strong"   { return New-Object System.Drawing.Font("Segoe UI", 11.25, [System.Drawing.FontStyle]::Bold) }  # 15px
        "body"          { return New-Object System.Drawing.Font("Segoe UI", 11.25, [System.Drawing.FontStyle]::Regular) } # 15px
        "caption"       { return New-Object System.Drawing.Font("Segoe UI", 9.75, [System.Drawing.FontStyle]::Regular) } # 13px
        "button-label"  { return New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold) }   # 14px
        default         { return New-Object System.Drawing.Font("Segoe UI", 11.25) }
    }
}

# space-1..space-8 do tokens.json, em px (mapeiam 1:1 pra pixels de tela com AutoScaleMode=None)
$Script:DSSpace1 = 4; $Script:DSSpace2 = 8; $Script:DSSpace3 = 12; $Script:DSSpace4 = 16
$Script:DSSpace6 = 24; $Script:DSSpace8 = 32
$Script:DSRadiusSm = 4; $Script:DSRadiusMd = 8; $Script:DSRadiusLg = 16; $Script:DSRadiusPill = 999

# Funcao pura (sem $Script:/closure state) que monta o GraphicsPath de um retangulo
# arredondado - reaproveitada tanto pro clip de Region (Set-CantoArredondado) quanto pro
# traco/preenchimento desenhado a mao em Paint (cards, loader). Seguro chamar de dentro de
# qualquer closure de evento assincrono: e so uma chamada de funcao normal, resolvida na
# hora (o bug de closure documentado em Enable-ModuleTabsStyling e so sobre variavel
# $Script: referenciada direto dentro do scriptblock, nao sobre chamadas de funcao).
function New-DSCaminhoArredondado {
    param([int]$X = 0, [int]$Y = 0, [int]$W, [int]$H, [int]$Raio)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = [Math]::Max(0, [Math]::Min($Raio, [Math]::Floor([Math]::Min($W, $H) / 2)))
    if ($r -le 0) {
        $path.AddRectangle((New-Object System.Drawing.Rectangle $X, $Y, $W, $H))
        return $path
    }
    $d = $r * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc(($X + $W - $d), $Y, $d, $d, 270, 90)
    $path.AddArc(($X + $W - $d), ($Y + $H - $d), $d, $d, 0, 90)
    $path.AddArc($X, ($Y + $H - $d), $d, $d, 90, 90)
    $path.CloseAllFigures()
    return $path
}

function Set-CantoArredondado {
    # WinForms nao tem border-radius nativo; aproxima o raio recortando a Region do
    # controle com um GraphicsPath. So usar em controles pequenos e sem filhos (botoes,
    # pills) - em paineis com controles dentro (cards, loader), region-clipping so remove
    # os cantos (onde nenhum filho fica), o resto da area/interacao segue normal.
    param($Controle, [int]$Raio)
    $Controle.Add_Resize({
        param($s, $e)
        if ($s.Width -le 1 -or $s.Height -le 1) { return }
        $path = New-DSCaminhoArredondado -W $s.Width -H $s.Height -Raio $Raio
        $s.Region = New-Object System.Drawing.Region $path
    }.GetNewClosure())
    # Aplica o clip uma vez, na hora, alem de so esperar o Resize: se o controle chamar
    # isso DEPOIS de Size/AutoSize ja terem disparado o (unico) Resize que teria feito o
    # trabalho, o handler acima nunca dispararia de novo (a janela e FixedSingle, o
    # usuario nao redimensiona) e o controle ficaria de canto reto pra sempre. Assim
    # funciona nas duas ordens de chamada.
    if ($Controle.Width -gt 1 -and $Controle.Height -gt 1) {
        $path = New-DSCaminhoArredondado -W $Controle.Width -H $Controle.Height -Raio $Raio
        $Controle.Region = New-Object System.Drawing.Region $path
    }
}

function New-DSBotao {
    # Botao no padrao Button do design system. Variante primary (brand-600, canto radius-lg,
    # sobe 1px no hover) ou disabled (disabled-bg, formato pill radius-pill) - as unicas duas
    # usadas hoje no app (ghost fica em Add-BarraVoltarHub, que e um link, nao um Button
    # preenchido).
    # Pintado 100% a mao em vez de Region-clip: Region nao tem antialiasing no GDI - o corte
    # arredondado sai visivelmente serrilhado, mais perceptivel agora com radius-lg (16px) e
    # radius-pill do que era com o radius-md (8px) da v1. Preenchimento e texto redesenhados
    # com SmoothingMode=AntiAlias por cima do fundo do PAI (lido no Paint, nao herdado do
    # FlatAppearance, que deixa de ter efeito visual - o Paint sempre roda depois e cobre tudo).
    param([string]$Texto, [string]$Variante = "primary")
    $paleta = $Script:DS
    $raioLg = $Script:DSRadiusLg
    $raioPill = $Script:DSRadiusPill

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Texto
    $btn.Font = DSFont "button-label"
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand

    if ($Variante -eq "primary") {
        # Fase controla a cor do preenchimento (normal/hover/pressed); PSCustomObject
        # mutavel porque cada Add_* abaixo e um GetNewClosure() separado - nenhum compartilha
        # uma variavel escalar simples atualizada por outro (mesmo padrao de $relogio ja usado
        # no arquivo).
        $estado = [PSCustomObject]@{ Fase = "normal" }
        # Feedback de interacao do README (Movimento): hover sobe o botao 1px, por delta
        # relativo (nao precisa saber a Location final, ainda nao atribuida neste ponto).
        $btn.Add_MouseEnter({ $estado.Fase = "hover"; $btn.Top -= 1; $btn.Invalidate() }.GetNewClosure())
        $btn.Add_MouseLeave({ $estado.Fase = "normal"; $btn.Top += 1; $btn.Invalidate() }.GetNewClosure())
        $btn.Add_MouseDown({ $estado.Fase = "pressed"; $btn.Invalidate() }.GetNewClosure())
        $btn.Add_MouseUp({ $estado.Fase = "hover"; $btn.Invalidate() }.GetNewClosure())
        $btn.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $corFundo = switch ($estado.Fase) { "pressed" { $paleta.Brand700 } "hover" { $paleta.Brand500 } default { $paleta.Brand600 } }
            $corPai = if ($s.Parent) { $s.Parent.BackColor } else { $paleta.Surface }
            $g.FillRectangle((New-Object System.Drawing.SolidBrush $corPai), 0, 0, $s.Width, $s.Height)
            $path = New-DSCaminhoArredondado -W $s.Width -H $s.Height -Raio $raioLg
            $g.FillPath((New-Object System.Drawing.SolidBrush $corFundo), $path)
            $fmt = New-Object System.Drawing.StringFormat
            $fmt.Alignment = [System.Drawing.StringAlignment]::Center
            $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
            # Sem isso, texto que nao cabe na largura do botao (rotulos mais longos, ex.:
            # "Gerar Fechamento >>") quebra em duas linhas e estoura a altura do botao em vez
            # de manter uma linha so com reticencias - botao e rotulo curto por definicao do
            # design system, nunca deveria mesmo precisar de 2 linhas.
            $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
            $fmt.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
            $rect = New-Object System.Drawing.RectangleF 0, 0, $s.Width, $s.Height
            $g.DrawString($s.Text, $s.Font, (New-Object System.Drawing.SolidBrush $paleta.InkOnBrand), $rect, $fmt)
        }.GetNewClosure())
    } else {
        # Fica "enabled" de proposito: um Button .Enabled=$false ignora BackColor/ForeColor
        # customizados e usa o cinza de sistema pro texto, quebrando o visual do pill. E so
        # um indicador de status (StatusBadge), nao uma acao real - fica inerte por nunca
        # receber Add_Click, nao por estar desabilitado.
        $btn.TabStop = $false
        $btn.Cursor = [System.Windows.Forms.Cursors]::Default
        $btn.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $corPai = if ($s.Parent) { $s.Parent.BackColor } else { $paleta.Surface }
            $g.FillRectangle((New-Object System.Drawing.SolidBrush $corPai), 0, 0, $s.Width, $s.Height)
            $path = New-DSCaminhoArredondado -W $s.Width -H $s.Height -Raio $raioPill
            $g.FillPath((New-Object System.Drawing.SolidBrush $paleta.DisabledBg), $path)
            $fmt = New-Object System.Drawing.StringFormat
            $fmt.Alignment = [System.Drawing.StringAlignment]::Center
            $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
            $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
            $fmt.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
            $rect = New-Object System.Drawing.RectangleF 0, 0, $s.Width, $s.Height
            $g.DrawString($s.Text, $s.Font, (New-Object System.Drawing.SolidBrush $paleta.DisabledInk), $rect, $fmt)
        }.GetNewClosure())
    }
    return $btn
}

function New-DSBotaoSecundario {
    # Acao utilitaria (Adicionar arquivo, Remover, Selecionar...) que nao e a CTA primaria
    # da tela - nao esta no components.md (so primary/ghost/disabled sao nomeados), mas usa
    # o mesmo vocabulario visual: contorno brand-600 sobre surface, sem preenchimento solido,
    # pra nao competir com o botao primary da tela.
    param([string]$Texto)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Texto
    $btn.Font = DSFont "button-label"
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = $Script:DS.BorderStrong
    $btn.FlatAppearance.MouseOverBackColor = $Script:DS.SurfaceSunken
    $btn.FlatAppearance.MouseDownBackColor = $Script:DS.Brand100
    $btn.BackColor = $Script:DS.Surface
    $btn.ForeColor = $Script:DS.Brand600
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-CantoArredondado -Controle $btn -Raio $Script:DSRadiusSm
    return $btn
}

function Set-DSGridStyle {
    # Aplica a paleta do design system a uma DataGridView: cabecalho brand-700/ink-on-brand
    # (igual ao topo de tela e ao cabecalho de tabela dos relatorios Excel), linhas surface,
    # selecao brand-100, bordas border-subtle.
    param($Grid)
    $Grid.BackgroundColor = $Script:DS.Surface
    $Grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Grid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $Grid.GridColor = $Script:DS.BorderSubtle
    $Grid.EnableHeadersVisualStyles = $false
    $Grid.ColumnHeadersDefaultCellStyle.BackColor = $Script:DS.Brand700
    $Grid.ColumnHeadersDefaultCellStyle.ForeColor = $Script:DS.InkOnBrand
    $Grid.ColumnHeadersDefaultCellStyle.Font = DSFont "body-strong"
    $Grid.ColumnHeadersHeight = 32
    $Grid.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
    $Grid.DefaultCellStyle.BackColor = $Script:DS.Surface
    $Grid.DefaultCellStyle.ForeColor = $Script:DS.Ink
    $Grid.DefaultCellStyle.Font = DSFont "body"
    $Grid.DefaultCellStyle.SelectionBackColor = $Script:DS.Brand100
    $Grid.DefaultCellStyle.SelectionForeColor = $Script:DS.Brand700
    $Grid.RowsDefaultCellStyle.BackColor = $Script:DS.Surface
    $Grid.AlternatingRowsDefaultCellStyle.BackColor = $Script:DS.SurfaceSunken
    $Grid.RowTemplate.Height = 26
}

function Set-DSCardVisual {
    # ModuleCard (README/components.md): borda border-subtle que sobe pra brand-500 no
    # hover, card sobe 2px - WinForms nao desenha borda nativa em cima de um Region
    # arredondado (BorderStyle so desenha reto), entao o traco e pintado a mao no Paint.
    # $Card.Location precisa ja estar definido quando esta funcao roda (o deslocamento de
    # hover e relativo a esse valor original, capturado uma vez aqui).
    param($Card, [int]$Raio = 16)
    $Card.BorderStyle = "None"
    $paleta = $Script:DS
    $xOriginal = $Card.Location.X
    $yOriginal = $Card.Location.Y
    $estado = [PSCustomObject]@{ CorBorda = $paleta.BorderSubtle }

    $Card.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-DSCaminhoArredondado -W ($s.Width - 1) -H ($s.Height - 1) -Raio $Raio
        $caneta = New-Object System.Drawing.Pen($estado.CorBorda, 1)
        $g.DrawPath($caneta, $path)
    }.GetNewClosure())

    $Card.Add_MouseEnter({
        $estado.CorBorda = $paleta.Brand500
        $Card.Location = New-Object System.Drawing.Point $xOriginal, ($yOriginal - 2)
        $Card.Invalidate()
    }.GetNewClosure())

    $Card.Add_MouseLeave({
        $estado.CorBorda = $paleta.BorderSubtle
        $Card.Location = New-Object System.Drawing.Point $xOriginal, $yOriginal
        $Card.Invalidate()
    }.GetNewClosure())
}

function New-DSIconeModulo {
    # Chip circular (o mesmo motivo de 3 barras crescentes do ProcessingLoader) antes do
    # titulo de cada ModuleCard - brand-100/brand-600 quando o modulo esta aberto,
    # disabled-bg/disabled-ink quando "Em breve"/"Em manutencao".
    param([bool]$Habilitado, [int]$Tamanho = 40)
    $corFundo = if ($Habilitado) { $Script:DS.Brand100 } else { $Script:DS.DisabledBg }
    $corGlifo = if ($Habilitado) { $Script:DS.Brand600 } else { $Script:DS.DisabledInk }

    $chip = New-Object System.Windows.Forms.Panel
    $chip.Size = New-Object System.Drawing.Size $Tamanho, $Tamanho
    $chip.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # Panel nao tem BackColor proprio definido (fica no cinza padrao do WinForms) - sem
        # apagar primeiro com o fundo do pai, o quadrado cinza do Panel aparecia por tras do
        # circulo em vez do branco/verde-claro do card.
        $corPai = if ($s.Parent) { $s.Parent.BackColor } else { $corFundo }
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $corPai), 0, 0, $s.Width, $s.Height)
        $pincelFundo = New-Object System.Drawing.SolidBrush $corFundo
        $g.FillEllipse($pincelFundo, 0, 0, ($s.Width - 1), ($s.Height - 1))

        $pincelBarra = New-Object System.Drawing.SolidBrush $corGlifo
        $larguraBarra = [Math]::Max(2, [Math]::Round($s.Width / 9.0))
        $gap = [Math]::Max(2, [Math]::Round($s.Width / 12.0))
        $baseY = [Math]::Round($s.Height * 0.72)
        $x = [Math]::Round($s.Width * 0.26)
        foreach ($fatorAltura in @(0.28, 0.42, 0.56)) {
            $h = [Math]::Round($s.Height * $fatorAltura)
            $g.FillRectangle($pincelBarra, $x, ($baseY - $h), $larguraBarra, $h)
            $x += $larguraBarra + $gap
        }
    }.GetNewClosure())
    return $chip
}

# Logo do Concilia ("Livro C", opcao 1a do handoff de design): um C montado com 5 linhas de
# lancamento (barra cheia em cima e embaixo, tres curtas no meio) e um visto de conciliado no
# vao aberto. Desenhado direto no GDI+ a partir da mesma geometria do SVG original (viewBox
# 48x48), entao sai nitido em qualquer tamanho - a mesma funcao gera o glifo do topo das telas,
# o icone da janela e (via make-icon.ps1) o app.ico do exe/atalhos.
#   Glifo: sem fundo, barras #0F3D25 + visto #1A8A4A (uso sobre fundo claro).
#   Tile:  quadrado #1A8A4A, barras brancas + visto #0F3D25 (icone de app/atalho).
function New-ConciliaLogoBitmap {
    param([int]$Tamanho = 40, [ValidateSet("Glifo", "Tile")][string]$Modo = "Glifo")
    $bmp = New-Object System.Drawing.Bitmap $Tamanho, $Tamanho, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        if ($Modo -eq "Tile") {
            $corBarras = [System.Drawing.Color]::White
            $corVisto = DSColor "#0F3D25"
            $fundo = New-Object System.Drawing.SolidBrush (DSColor "#1A8A4A")
            $g.FillRectangle($fundo, 0, 0, $Tamanho, $Tamanho)
            $fundo.Dispose()
            $lado = $Tamanho * 0.78
            $desloc = ($Tamanho - $lado) / 2.0
        } else {
            $corBarras = DSColor "#0F3D25"
            $corVisto = DSColor "#1A8A4A"
            $lado = [double]$Tamanho
            $desloc = 0.0
        }
        $e = $lado / 48.0
        $pincel = New-Object System.Drawing.SolidBrush $corBarras
        # x, y, largura, altura no viewBox 48x48
        $barras = @(@(5, 5, 38, 5), @(5, 13.5, 12, 5), @(5, 22, 12, 5), @(5, 30.5, 12, 5), @(5, 39, 38, 5))
        foreach ($b in $barras) {
            $g.FillRectangle($pincel, [single]($desloc + $b[0] * $e), [single]($desloc + $b[1] * $e), [single]($b[2] * $e), [single]($b[3] * $e))
        }
        $pincel.Dispose()
        $caneta = New-Object System.Drawing.Pen $corVisto, ([single](5.5 * $e))
        $caneta.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
        $caneta.EndCap = [System.Drawing.Drawing2D.LineCap]::Square
        $caneta.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
        $pontos = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF ([single]($desloc + 22 * $e)), ([single]($desloc + 24.5 * $e))),
            (New-Object System.Drawing.PointF ([single]($desloc + 28 * $e)), ([single]($desloc + 30.5 * $e))),
            (New-Object System.Drawing.PointF ([single]($desloc + 42 * $e)), ([single]($desloc + 15 * $e)))
        )
        $g.DrawLines($caneta, $pontos)
        $caneta.Dispose()
    } finally { $g.Dispose() }
    return $bmp
}

# Cache do glifo do topo das telas (40px) pra nao redesenhar toda vez que uma tela e aberta.
$Script:AppIconBitmapCache = $null
function Get-AppIconBitmap {
    # Falha silenciosa: se nao der pra desenhar, o topo da tela some sem o icone em vez de
    # travar o app (mesma filosofia de Test-AtualizacaoDisponivel).
    if ($null -ne $Script:AppIconBitmapCache) { return $Script:AppIconBitmapCache }
    try { $Script:AppIconBitmapCache = New-ConciliaLogoBitmap -Tamanho 40 -Modo Glifo }
    catch { $Script:AppIconBitmapCache = $null }
    return $Script:AppIconBitmapCache
}

function Get-AppFormIcon {
    # Icone da barra de titulo/barra de tarefas da janela principal (tile verde). O do arquivo
    # .exe/atalho vem do app.ico embutido pelo ps2exe - este e so o da janela em execucao.
    try {
        $bmp = New-ConciliaLogoBitmap -Tamanho 32 -Modo Tile
        return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    } catch { return $null }
}

function Get-DSTopoAltura {
    # Altura do painel do padrao "Topo" (icone + titulo + [subtitulo] + regua) - calculada a
    # parte de Add-DSTopo pra quem posiciona conteudo por pixel absoluto embaixo dele
    # (New-CardGridPanel) saber o deslocamento sem duplicar os numeros em dois lugares. Usa
    # Font.Height (metrica direta da fonte, sempre disponivel, sem precisar renderizar um
    # Label) pro espaco do titulo - tem que bater com o que Add-DSTopo realmente usa pra
    # posicionar o subtitulo, senao o subtitulo calcula uma posicao que nao cabe no espaco
    # que esta funcao reservou (jah aconteceu: com title-app, 32px, o subtitulo acabava caindo
    # em cima da regua porque o "40" fixo aqui nao dava conta da fonte grande).
    param([switch]$ComSubtitulo, [string]$FonteTitulo = "title-module")
    $alturaTitulo = (DSFont $FonteTitulo).Height
    $altura = $Script:DSSpace6 + [Math]::Max(40, $alturaTitulo) + $Script:DSSpace4 + 3
    if ($ComSubtitulo) { $altura += (DSFont "caption").Height + $Script:DSSpace2 }
    return $altura
}

function Add-DSTopo {
    # Padrao "Topo" do README (Reformulacao de layout / Padroes de tela): icone do
    # mascote (~40px) + nome direto sobre surface-page, sem barra solida, com uma regua de
    # brand-600 (space-1/4px) sob o texto - substitui a antiga faixa cheia brand-700.
    # Dock=Top: o WinForms doca na ordem inversa a que os controles sao adicionados ao
    # Controls (o ULTIMO adicionado fica mais externo/no topo - ver nota identica em
    # Add-BarraVoltarHub). Chamar isso DEPOIS de Add-BarraVoltarHub deixa o topo (icone+
    # titulo) no topo da janela, com a barra "Voltar" (adicionada antes) logo abaixo dele.
    param($Form, [string]$Titulo, [string]$FonteTitulo = "title-module", [string]$Subtitulo = "")
    $comSub = [bool]$Subtitulo
    $altura = Get-DSTopoAltura -ComSubtitulo:$comSub -FonteTitulo $FonteTitulo

    $painel = New-Object System.Windows.Forms.Panel
    $painel.Dock = "Top"
    $painel.Height = $altura
    $painel.BackColor = $Script:DS.SurfacePage
    $Form.Controls.Add($painel)

    $xTexto = $Script:DSSpace8
    $icone = Get-AppIconBitmap
    if ($icone) {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Image = $icone
        $pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pic.Size = New-Object System.Drawing.Size 40, 40
        $pic.Location = New-Object System.Drawing.Point $Script:DSSpace8, $Script:DSSpace6
        $painel.Controls.Add($pic)
        $xTexto = $Script:DSSpace8 + 40 + $Script:DSSpace6
    }

    $lblTitulo = New-Object System.Windows.Forms.Label
    $lblTitulo.Text = $Titulo
    $lblTitulo.Font = DSFont $FonteTitulo
    $lblTitulo.ForeColor = $Script:DS.Ink
    $lblTitulo.AutoSize = $true
    $lblTitulo.Location = New-Object System.Drawing.Point $xTexto, ($Script:DSSpace6 - 4)
    $painel.Controls.Add($lblTitulo)

    if ($comSub) {
        $lblSub = New-Object System.Windows.Forms.Label
        $lblSub.Text = $Subtitulo
        $lblSub.Font = DSFont "caption"
        $lblSub.ForeColor = $Script:DS.InkMuted
        $lblSub.AutoSize = $true
        # Y calculado a partir de Font.Height (metrica direta da fonte do titulo, nao do
        # Control.Height AutoSize - ver nota em Get-DSTopoAltura, que precisa prever o MESMO
        # numero pra reservar espaco suficiente no painel) em vez do numero fixo antigo
        # (space6+40-20=44), que ficava ACIMA do fim real do titulo e causava sobreposicao
        # vertical - e como a label adicionada primeiro ($lblTitulo) fica na FRENTE no z-order
        # (nao atras, como seria intuitivo - mesma licao do BringToFront do rodape da Home), o
        # pedaço sobreposto do subtitulo ficava escondido atras do titulo.
        $lblSub.Location = New-Object System.Drawing.Point $xTexto, ($lblTitulo.Location.Y + $lblTitulo.Font.Height + $Script:DSSpace1)
        $painel.Controls.Add($lblSub)
    }

    $regua = New-Object System.Windows.Forms.Panel
    $regua.BackColor = $Script:DS.Brand600
    $regua.Height = 3
    $regua.Dock = "Bottom"
    $painel.Controls.Add($regua)

    return $painel
}

function New-DSProcessingLoader {
    # ProcessingLoader (components.md): a unica animacao continua do produto - 5 barras
    # brand-100/brand-500/brand-600/brand-500/brand-100 sobem/descem em cascata (~1s,
    # defasadas por barra) como um equalizador, com um rotulo em pill brand-700/ink-on-brand
    # embaixo (reticencias em cascata). So aparece enquanto o app esta processando um
    # arquivo, nunca como spinner generico em outro lugar (ver README # Movimento).
    # Retorna o Panel (Dock=Fill) pronto pra sobrepor o conteudo da aba atual via
    # .Controls.Add + .BringToFront(); quem chamar precisa dar .Dispose() nele quando o
    # processamento terminar (isso para e libera o Timer interno via o evento Disposed).
    param([string]$Texto = "Processando arquivos")
    $paleta = $Script:DS

    $overlay = New-Object System.Windows.Forms.Panel
    $overlay.Dock = "Fill"
    $overlay.BackColor = $paleta.Surface

    # Raios capturados em local antes de qualquer closure de evento assincrono (Paint,
    # Resize): $Script:DSRadiusLg/Md referenciado direto dentro de um scriptblock
    # GetNewClosure() que so dispara depois, pelo message loop, e o mesmo bug de escopo ja
    # documentado em Enable-ModuleTabsStyling - $Script: sai nulo no exe compilado.
    $raioLg = $Script:DSRadiusLg
    $raioMd = $Script:DSRadiusMd

    $cartao = New-Object System.Windows.Forms.Panel
    $cartao.Size = New-Object System.Drawing.Size 280, 168
    $cartao.BackColor = $paleta.Surface
    # Sem Region-clip de proposito (ver nota em New-DSBotao): a Region do GDI nao tem
    # antialiasing, entao o corte arredondado sairia serrilhado. O traco da borda abaixo ja
    # e desenhado com AntiAlias, e o overlay ao redor e da mesma cor (Surface), entao os
    # "cantos quadrados" por tras da borda ficam invisiveis sem precisar apagar nada.
    $overlay.Controls.Add($cartao)
    $overlay.Add_Resize({
        param($s, $e)
        $cartao.Location = New-Object System.Drawing.Point ([Math]::Round(($s.Width - $cartao.Width) / 2)), ([Math]::Round(($s.Height - $cartao.Height) / 2))
    }.GetNewClosure())
    $cartao.Location = New-Object System.Drawing.Point ([Math]::Round(($overlay.Width - $cartao.Width) / 2)), ([Math]::Round(($overlay.Height - $cartao.Height) / 2))

    $cartao.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-DSCaminhoArredondado -W ($s.Width - 1) -H ($s.Height - 1) -Raio $raioLg
        $caneta = New-Object System.Drawing.Pen($paleta.BorderSubtle, 1)
        $g.DrawPath($caneta, $path)
    }.GetNewClosure())

    # 5 barras equalizador - estado do "relogio" da animacao (tick count) num objeto
    # mutavel pra ser lido pelo Paint e escrito pelo Timer (duas closures GetNewClosure()
    # separadas nao compartilham uma variavel escalar simples, capturada por valor em cada
    # uma; um PSCustomObject com propriedade mutavel resolve o compartilhamento).
    $coresBarras = @($paleta.Brand100, $paleta.Brand500, $paleta.Brand600, $paleta.Brand500, $paleta.Brand100)
    $numBarras = 5
    $larguraBarra = 16
    $gapBarra = $Script:DSSpace3
    $alturaMax = 48
    $largutaTotal = ($larguraBarra * $numBarras) + ($gapBarra * ($numBarras - 1))
    $relogio = [PSCustomObject]@{ N = 0 }

    $painelBarras = New-Object System.Windows.Forms.Panel
    $painelBarras.Size = New-Object System.Drawing.Size $largutaTotal, $alturaMax
    $painelBarras.Location = New-Object System.Drawing.Point ([Math]::Round(($cartao.Width - $largutaTotal) / 2)), 28
    $painelBarras.BackColor = $paleta.Surface
    $cartao.Controls.Add($painelBarras)

    $painelBarras.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        for ($i = 0; $i -lt $numBarras; $i++) {
            $fase = ($relogio.N * 0.15) + ($i * 1.05)
            $onda = ([Math]::Sin($fase) + 1) / 2
            $h = [Math]::Max(8, [Math]::Round($alturaMax * (0.32 + 0.68 * $onda)))
            $x = $i * ($larguraBarra + $gapBarra)
            $y = $alturaMax - $h
            $pincel = New-Object System.Drawing.SolidBrush $coresBarras[$i]
            $path = New-DSCaminhoArredondado -X $x -Y $y -W $larguraBarra -H $h -Raio $raioMd
            $g.FillPath($pincel, $path)
        }
    }.GetNewClosure())

    $raioPill = $Script:DSRadiusPill
    $pillTexto = New-Object System.Windows.Forms.Label
    $pillTexto.Font = DSFont "caption"
    $pillTexto.AutoSize = $true
    $pillTexto.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $pillTexto.Padding = New-Object System.Windows.Forms.Padding 14, 6, 14, 6
    $pillTexto.Text = $Texto
    $cartao.Controls.Add($pillTexto)
    # Sem Region-clip de proposito (ver nota em New-DSBotao): preenchimento e texto
    # redesenhados a mao com AntiAlias por cima do fundo do pai, em vez de confiar no recorte
    # serrilhado de Region + BackColor nativo do Label.
    $pillTexto.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $corPai = if ($s.Parent) { $s.Parent.BackColor } else { $paleta.Surface }
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $corPai), 0, 0, $s.Width, $s.Height)
        $path = New-DSCaminhoArredondado -W $s.Width -H $s.Height -Raio $raioPill
        $g.FillPath((New-Object System.Drawing.SolidBrush $paleta.Brand700), $path)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF 0, 0, $s.Width, $s.Height
        $g.DrawString($s.Text, $s.Font, (New-Object System.Drawing.SolidBrush $paleta.InkOnBrand), $rect, $fmt)
    }.GetNewClosure())
    $cartao.Add_Resize({
        param($s, $e)
        $pillTexto.Location = New-Object System.Drawing.Point ([Math]::Round(($s.Width - $pillTexto.Width) / 2)), 108
    }.GetNewClosure())
    $pillTexto.Location = New-Object System.Drawing.Point ([Math]::Round(($cartao.Width - $pillTexto.Width) / 2)), 108

    $temporizador = New-Object System.Windows.Forms.Timer
    $temporizador.Interval = 60
    $temporizador.Add_Tick({
        $relogio.N += 1
        $numPontos = [Math]::Floor($relogio.N / 8) % 4
        $pillTexto.Text = $Texto + ("." * $numPontos)
        $pillTexto.Invalidate()
        $painelBarras.Invalidate()
    }.GetNewClosure())
    $temporizador.Start()
    # Panel/Control so expoe o evento publico "Disposed" (pos-Dispose) - "Disposing" nao existe
    # como evento publico (e so um metodo protegido no Component base), entao Add_Disposing
    # lancava MethodException em runtime toda vez que um loader era criado (nunca pego antes
    # porque o clique real que dispara isso nao pode ser simulado neste ambiente - ver nota em
    # project_design_system_application sobre hover/loader so verificados por revisao de codigo).
    $overlay.Add_Disposed({ $temporizador.Stop(); $temporizador.Dispose() }.GetNewClosure())

    return $overlay
}

function Enable-ModuleTabsStyling {
    # Padrao ModuleTabs: cada aba mostra um circulo numerado + o nome da etapa. Aba concluida
    # (ja visitada): circulo brand-100/brand-700. Aba ativa: circulo brand-600/ink-on-brand +
    # sublinhado brand-600. Aba futura (nunca visitada): circulo disabled-bg/disabled-ink.
    # WinForms nao estiliza aba nativamente - usa DrawMode=OwnerDrawFixed. As 3 abas sao
    # sempre navegaveis livremente (nao ha trava sequencial), entao "concluida" aqui significa
    # "ja visitada alguma vez", nunca volta a "futura" (guardado num HashSet que so cresce).
    param($TabControl)

    $visitadas = New-Object 'System.Collections.Generic.HashSet[int]'
    $visitadas.Add(0) | Out-Null
    # Copia local da paleta pro closure capturar por valor via GetNewClosure(): $Script:DS
    # direto dentro de um event handler assincrono (dispara bem depois, pelo message loop do
    # WinForms) voltava nulo no exe compilado, mesmo funcionando em codigo executado na hora.
    $paleta = $Script:DS
    $raioPill = $Script:DSRadiusPill

    $TabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $TabControl.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $TabControl.ItemSize = New-Object System.Drawing.Size(190, 40)
    $TabControl.Padding = New-Object System.Drawing.Point 18, 6

    $TabControl.Add_SelectedIndexChanged({
        param($s, $e)
        $visitadas.Add($s.SelectedIndex) | Out-Null
        $s.Invalidate()
    }.GetNewClosure())

    $TabControl.Add_DrawItem({
        param($s, $e)
        $tabPage = $s.TabPages[$e.Index]
        $rect = $e.Bounds
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $ehAtiva = ($e.Index -eq $s.SelectedIndex)
        $ehVisitada = $visitadas.Contains($e.Index)

        if ($ehAtiva) { $corCirculo = $paleta.Brand600; $corNumero = $paleta.InkOnBrand; $corTexto = $paleta.Brand700 }
        elseif ($ehVisitada) { $corCirculo = $paleta.Brand100; $corNumero = $paleta.Brand700; $corTexto = $paleta.Brand700 }
        else { $corCirculo = $paleta.DisabledBg; $corNumero = $paleta.DisabledInk; $corTexto = $paleta.InkMuted }
        $corFundo = $paleta.Surface

        # Cor sempre pre-atribuida a uma variavel simples antes de New-Object SolidBrush: um
        # encadeamento de propriedade ($Script:DS.Xyz) direto como argumento posicional do
        # New-Object, dentro de uma chamada de metodo aninhada como esta, falhava com "Um
        # construtor nao foi encontrado" no exe compilado (apesar de funcionar em outros
        # lugares do arquivo fora desse aninhamento especifico).
        $pincelFundo = New-Object System.Drawing.SolidBrush $corFundo
        $g.FillRectangle($pincelFundo, $rect)

        # Aba ativa (v2 do design system): pill brand-100 atras do item inteiro, em vez do
        # sublinhado da v1 - inset de 4px pra pill nao encostar nas abas vizinhas.
        if ($ehAtiva) {
            $pillRect = New-Object System.Drawing.Rectangle ($rect.Left + 4), ($rect.Top + 4), ($rect.Width - 8), ($rect.Height - 8)
            $pincelPill = New-Object System.Drawing.SolidBrush $paleta.Brand100
            $pillPath = New-DSCaminhoArredondado -X $pillRect.X -Y $pillRect.Y -W $pillRect.Width -H $pillRect.Height -Raio $raioPill
            $g.FillPath($pincelPill, $pillPath)
        }

        $diametro = 22
        $cx = $rect.Left + 16
        $cy = $rect.Top + [Math]::Round($rect.Height / 2)
        $circRect = New-Object System.Drawing.Rectangle ($cx - [Math]::Round($diametro / 2)), ($cy - [Math]::Round($diametro / 2)), $diametro, $diametro
        $pincelCirculo = New-Object System.Drawing.SolidBrush $corCirculo
        $g.FillEllipse($pincelCirculo, $circRect)
        $numFormat = New-Object System.Drawing.StringFormat
        $numFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $numFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        $pincelNumero = New-Object System.Drawing.SolidBrush $corNumero
        $circRectF = New-Object System.Drawing.RectangleF $circRect.X, $circRect.Y, $circRect.Width, $circRect.Height
        $g.DrawString("$($e.Index + 1)", (DSFont "button-label"), $pincelNumero, $circRectF, $numFormat)

        $textoRect = New-Object System.Drawing.RectangleF ($cx + [Math]::Round($diametro / 2) + 8), $rect.Top, ($rect.Width - $diametro - 30), $rect.Height
        $txtFormat = New-Object System.Drawing.StringFormat
        $txtFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        $txtFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
        # Sem NoWrap, nomes de aba mais longos ("Mapeamento de unidade") quebravam em duas
        # linhas e vazavam pra cima da aba seguinte, em vez de truncar com reticencias numa
        # linha so (o Trimming acima so faz efeito com NoWrap - sem ele, DrawString prefere
        # quebrar linha a truncar).
        $txtFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
        $pincelTexto = New-Object System.Drawing.SolidBrush $corTexto
        $g.DrawString($tabPage.Text, (DSFont "button-label"), $pincelTexto, $textoRect, $txtFormat)
    }.GetNewClosure())
}

# ============================================================================
# VERSAO E ATUALIZACAO
# ============================================================================
# Bump manual a cada release publicado (ver publish-update.ps1). Mostrado na tela Home e
# usado pra decidir se ha versao mais nova disponivel no repositorio publico do GitHub.
$Script:AppVersion = "1.5.0"
$Script:UpdateVersionUrl = "https://raw.githubusercontent.com/eduardobettinirodrigues-ai/Finantron-Updates/main/version.json"
$Script:UpdateInstallerUrl = "https://raw.githubusercontent.com/eduardobettinirodrigues-ai/Finantron-Updates/main/ConciliacaoVendas_Instalador.exe"

function Test-AtualizacaoDisponivel {
    # Checagem de versao NAO BLOQUEANTE: qualquer falha (sem internet, repo fora do ar,
    # timeout) cai no catch e o app segue normal, sem avisar nada - nunca trava por causa
    # disso. So retorna Disponivel=$true se a versao remota for estritamente maior.
    try {
        $resp = Invoke-RestMethod -Uri $Script:UpdateVersionUrl -TimeoutSec 4 -Headers @{ "Cache-Control" = "no-cache" } -ErrorAction Stop
        $remota = [version]"$($resp.versao)"
        $local = [version]$Script:AppVersion
        if ($remota -gt $local) {
            return [PSCustomObject]@{ Disponivel = $true; Versao = "$($resp.versao)"; Notas = "$($resp.notas)" }
        }
    } catch {}
    return [PSCustomObject]@{ Disponivel = $false }
}

# Memoiza o resultado da checagem (uma unica chamada de rede por sessao do app, nao uma por
# tela aberta) pra poder mostrar o aviso de atualizacao em qualquer tela visitada depois da
# Home, nao so no primeiro instante em que o app abre.
$Script:UpdateInfoCache = $null
function Get-AtualizacaoInfoCache {
    if ($null -eq $Script:UpdateInfoCache) { $Script:UpdateInfoCache = Test-AtualizacaoDisponivel }
    return $Script:UpdateInfoCache
}

function Set-AtualizacaoInfoCache {
    # Funcao dedicada (em vez de escrever $Script:UpdateInfoCache direto de dentro do Timer
    # de New-HomePanel) por precaucao: o bug de closure ja documentado (Enable-ModuleTabsStyling)
    # e sobre LEITURA de $Script: dentro de um closure assincrono, mas como a causa raiz nunca
    # foi totalmente entendida, evitar qualquer acesso direto a $Script: (leitura ou escrita)
    # de dentro de um scriptblock de evento assincrono e mais seguro - chamada de funcao
    # normal, resolvida na hora, sempre funcionou nos outros casos ja testados.
    param($Info)
    $Script:UpdateInfoCache = $Info
}

function Invoke-AtualizacaoApp {
    # Baixa e inicia o instalador, depois fecha o app inteiro (nao so a tela atual) pra nao
    # deixar o processo em execucao competindo com a instalacao. Usado tanto pelo aviso inicial
    # da Home quanto pelo link persistente nas demais telas.
    param([string]$InstallerUrl)
    try {
        $tempInstaller = Join-Path $env:TEMP "Concilia_Instalador.exe"
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $tempInstaller -TimeoutSec 60
        Start-Process $tempInstaller
        [System.Windows.Forms.Application]::Exit()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Não foi possível baixar a atualização: $($_.Exception.Message)", "Erro") | Out-Null
    }
}

function New-DSLinkAtualizacao {
    # Link ghost (brand-600 sobre surface, igual ao BackButton) que avisa que ha uma versao
    # mais nova publicada - usado nas telas de navegacao (Relatorios, Conciliacao, Fechamento)
    # pra o usuario ver o aviso mesmo se tiver ignorado o dialogo inicial da Home ou estiver no
    # meio de um modulo quando a nova versao for publicada.
    param($Upd)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nova versão disponível ($($Upd.Versao)) — clique para atualizar"
    $lbl.Font = DSFont "caption"
    $lbl.ForeColor = $Script:DS.Brand600
    $lbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lbl.AutoSize = $true
    $urlInstalador = $Script:UpdateInstallerUrl
    $lbl.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show("Baixar e instalar a atualização agora? O aplicativo será fechado durante a instalação.", "Atualizar Concilia", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { Invoke-AtualizacaoApp -InstallerUrl $urlInstalador }
    }.GetNewClosure())
    return $lbl
}

# ============================================================================
# CONFIG
# ============================================================================
function Get-AppDirectory {
    # $PSScriptRoot fica vazio quando compilado pelo ps2exe (o exe nao roda como um
    # arquivo .ps1 comum), entao usamos o caminho real do processo em execucao.
    if ($PSScriptRoot) { return $PSScriptRoot }
    try {
        $procPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($procPath) { return [System.IO.Path]::GetDirectoryName($procPath) }
    } catch {}
    return (Get-Location).Path
}
$Script:ConfigPath = Join-Path (Get-AppDirectory) "config.json"

$Script:DefaultConfig = @{
    PdcUnidade = @{
        "10738002" = "MOOCA"; "10738005" = "MOOCA"
        "10738001" = "VILA MOURA"; "10738003" = "VILA MOURA"; "10738004" = "VILA MOURA"; "10752923" = "VILA MOURA"
    }
    EstabelecimentoUnidade = @{
        "92149034" = "MOOCA"; "92414076" = "VILA MOURA"
    }
    # Senha por nome de banco (ex.: "C6" = "<senha do arquivo>"), nao mais um campo unico compartilhado -
    # cada banco identificado no arquivo usa sua propria senha salva.
    SenhasBanco = @{}
}

function Load-AppConfig {
    if (Test-Path $Script:ConfigPath) {
        try {
            $raw = Get-Content $Script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pdc = @{}
            $raw.PdcUnidade.PSObject.Properties | ForEach-Object { $pdc[$_.Name] = $_.Value }
            $est = @{}
            $raw.EstabelecimentoUnidade.PSObject.Properties | ForEach-Object { $est[$_.Name] = $_.Value }
            $senhas = @{}
            if ($raw.PSObject.Properties["SenhasBanco"]) { $raw.SenhasBanco.PSObject.Properties | ForEach-Object { $senhas[$_.Name] = $_.Value } }
            return @{ PdcUnidade = $pdc; EstabelecimentoUnidade = $est; SenhasBanco = $senhas }
        } catch { return $Script:DefaultConfig.Clone() }
    }
    return $Script:DefaultConfig.Clone()
}

function Save-AppConfig {
    param($PdcUnidade, $EstabelecimentoUnidade, $SenhasBanco = @{})
    $obj = @{ PdcUnidade = $PdcUnidade; EstabelecimentoUnidade = $EstabelecimentoUnidade; SenhasBanco = $SenhasBanco }
    $obj | ConvertTo-Json | Out-File -FilePath $Script:ConfigPath -Encoding UTF8
}

# ============================================================================
# PARSING HELPERS
# ============================================================================
function Get-BRDecimal {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return 0.0 }
    $t = $s -replace "R\$", ""
    $t = $t.Trim()
    if ($t -eq "" -or $t -eq "-") { return 0.0 }
    $neg = $false
    if ($t.StartsWith("-")) { $neg = $true; $t = $t.Substring(1).Trim() }
    $t = $t -replace "\.", ""
    $t = $t -replace ",", "."
    $v = 0.0
    [void][double]::TryParse($t, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)
    if ($neg) { $v = -$v }
    return $v
}

function ConvertTo-DecimalAny {
    param($v)
    if ($null -eq $v) { return 0.0 }
    if ($v -is [double]) { return [double]$v }
    if ($v -is [int]) { return [double]$v }
    return Get-BRDecimal "$v"
}

function ConvertTo-DateSafe {
    param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [double]) {
        try { return [DateTime]::FromOADate($v).Date } catch { return $null }
    }
    $s = "$v".Trim()
    if ($s -eq "") { return $null }
    $dt = [DateTime]::MinValue
    $fmts = @("yyyy-MM-dd","dd/MM/yyyy","d/M/yyyy","yyyy-MM-dd HH:mm:ss","dd/MM/yyyy HH:mm:ss")
    foreach ($f in $fmts) {
        if ([DateTime]::TryParseExact($s, $f, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt.Date }
    }
    if ([DateTime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt.Date }
    return $null
}

function ConvertTo-TimeSafe {
    param($v)
    if ($null -eq $v) { return [TimeSpan]::Zero }
    if ($v -is [double]) {
        $frac = $v - [Math]::Floor($v)
        $totalSeconds = [Math]::Round($frac * 86400)
        return [TimeSpan]::FromSeconds($totalSeconds)
    }
    $s = "$v".Trim()
    if ($s -eq "") { return [TimeSpan]::Zero }
    $ts = [TimeSpan]::Zero
    if ([TimeSpan]::TryParse($s, [ref]$ts)) { return $ts }
    return [TimeSpan]::Zero
}

function Remove-Diacriticos {
    param([string]$Texto)
    if ([string]::IsNullOrEmpty($Texto)) { return "" }
    $normalized = $Texto.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function ConvertTo-FormaCanonica {
    param([string]$Origem, [string]$Raw = "", [string]$Modalidade = "", [string]$Produto = "")
    $r = (Remove-Diacriticos "$Raw").ToUpperInvariant()
    $m = (Remove-Diacriticos "$Modalidade").ToUpperInvariant()
    $p = (Remove-Diacriticos "$Produto").ToUpperInvariant()
    if ($Origem -eq "Sistema") {
        if ($r -match "DINHEIRO") { return "DINHEIRO" }
        if ($r -match "DEBITO") { return "DÉBITO" }
        if ($r -match "CRED") { return "CRÉDITO" }
        if ($r -match "PIX") { return "PIX" }
        if ($r -match "ALIM|REF") { return "VOUCHER" }
        if ($r -match "CONTA") { return "CONTA" }
        return "OUTROS ($Raw)"
    } else {
        if ($m -match "CRED") { return "CRÉDITO" }
        if ($m -match "DEB") { return "DÉBITO" }
        if ($m -match "PIX") { return "PIX" }
        if ($m -match "VOUCHER" -or $p -match "VOUCHER|REFEI|ALIMENT|MULTIPL") { return "VOUCHER" }
        return "OUTROS ($Modalidade)"
    }
}

function Get-UnidadeFromFileName {
    param([string]$FileName)
    $n = $FileName.ToLowerInvariant()
    if ($n -match "mooca") { return "MOOCA" }
    if ($n -match "moura") { return "VILA MOURA" }
    return ""
}

function Add-ArquivosAoGrid {
    # Adiciona arquivos .xlsx/.xls a um grid do formulario (usado tanto pelo botao "Adicionar..."
    # quanto pelo arrastar-e-soltar), evitando duplicatas e ignorando o que nao for planilha.
    # A coluna visivel "Arquivo" mostra so o nome; o caminho completo vai na coluna oculta
    # "ArquivoCompleto".
    param($Grid, [string[]]$Paths, [bool]$DetectUnidade = $false)
    foreach ($f in $Paths) {
        if (-not (Test-Path $f -PathType Leaf)) { continue }
        $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
        if ($ext -ne ".xlsx" -and $ext -ne ".xls") { continue }
        $jaExiste = $false
        foreach ($row in $Grid.Rows) { if ("$($row.Cells['ArquivoCompleto'].Value)" -eq $f) { $jaExiste = $true; break } }
        if ($jaExiste) { continue }
        $idx = $Grid.Rows.Add()
        $Grid.Rows[$idx].Cells["Arquivo"].Value = [System.IO.Path]::GetFileName($f)
        $Grid.Rows[$idx].Cells["ArquivoCompleto"].Value = $f
        if ($DetectUnidade) {
            $Grid.Rows[$idx].Cells["Unidade"].Value = Get-UnidadeFromFileName ([System.IO.Path]::GetFileName($f))
        }
    }
}

function Get-UnidadeSlugUpper {
    # Ex.: "VILA MOURA" -> "VILA_MOURA" (usado no ID Saldo)
    param([string]$Unidade)
    return ($Unidade -replace " ", "_")
}

function Get-UnidadeSlugLower {
    # Ex.: "VILA MOURA" -> "vilamoura" (usado no RID)
    param([string]$Unidade)
    return (Remove-Diacriticos ($Unidade -replace " ", "")).ToLowerInvariant()
}

function Format-ValorPonto {
    # Formata valor com ponto decimal (usado nos textos de Descricao, que seguem esse padrao no modelo de referencia)
    param([double]$Valor)
    return $Valor.ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)
}

# ============================================================================
# EXCEL IO
# ============================================================================
function New-ExcelApp {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $excel.AutomationSecurity = 3
    return $excel
}

function Close-ExcelApp {
    param($ExcelApp)
    try { $ExcelApp.Quit() } catch {}
    try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ExcelApp) | Out-Null } catch {}
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

function Unblock-FileSafe {
    param([string]$Path)
    try { Unblock-File -Path $Path -ErrorAction SilentlyContinue } catch {}
}

function Get-RealExcelExtension {
    # Detecta o formato real pelo cabecalho binario (assinatura), pois arquivos exportados
    # por bancos as vezes usam extensao .xlsx em arquivos que sao na verdade .xls (OLE) - abrir
    # esse tipo de arquivo direto pelo nome errado trava o Excel numa caixa de dialogo invisivel.
    param([string]$Path)
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $buf = New-Object byte[] 8
        [void]$fs.Read($buf, 0, 8)
        $fs.Close()
    } catch { return ".xlsx" }
    if ($buf[0] -eq 0xD0 -and $buf[1] -eq 0xCF -and $buf[2] -eq 0x11 -and $buf[3] -eq 0xE0) { return ".xls" }
    if ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B) { return ".xlsx" }
    return [System.IO.Path]::GetExtension($Path)
}

function Open-WorkbookRobust {
    # Algumas planilhas (ex.: exportacao do C6) sao protegidas por senha e ficam
    # armazenadas em contêiner OLE mesmo com extensao .xlsx. Sem a senha certa, o Excel
    # trava esperando uma caixa de dialogo invisivel (Visible=$false) que nunca e respondida.
    param($ExcelApp, [string]$Path, [string]$Password = "")
    Unblock-FileSafe -Path $Path
    $realExt = Get-RealExcelExtension -Path $Path
    $currentExt = [System.IO.Path]::GetExtension($Path)
    $missing = [System.Type]::Missing
    $openPath = $Path
    $tempPath = $null
    if ($realExt -ne $currentExt) {
        $tempPath = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName() + $realExt)
        Copy-Item -Path $Path -Destination $tempPath -Force
        Unblock-FileSafe -Path $tempPath
        $openPath = $tempPath
    }
    if ($Password) {
        $wb = $ExcelApp.Workbooks.Open($openPath, 0, $true, $missing, $Password)
    } else {
        $wb = $ExcelApp.Workbooks.Open($openPath, 0, $true)
    }
    return [PSCustomObject]@{ Workbook = $wb; TempPath = $tempPath }
}

function Close-WorkbookCtx {
    param($Ctx)
    try { $Ctx.Workbook.Close($false) } catch {}
    if ($Ctx.TempPath -and (Test-Path $Ctx.TempPath)) { Remove-Item $Ctx.TempPath -Force -ErrorAction SilentlyContinue }
}

function Find-HeaderRow {
    param($Worksheet, [string[]]$RequiredHeaders, [int]$MaxScanRows = 30)
    $used = $Worksheet.UsedRange
    $maxCol = $used.Columns.Count
    $maxRow = [Math]::Min($MaxScanRows, $used.Rows.Count)
    for ($r = 1; $r -le $maxRow; $r++) {
        $map = @{}
        for ($c = 1; $c -le $maxCol; $c++) {
            $t = "$($Worksheet.Cells.Item($r, $c).Text)".Trim()
            if ($t -ne "") { $map[$t.ToLowerInvariant()] = $c }
        }
        $allFound = $true
        foreach ($h in $RequiredHeaders) {
            if (-not $map.ContainsKey($h.ToLowerInvariant())) { $allFound = $false; break }
        }
        if ($allFound) { return [PSCustomObject]@{ Row = $r; Map = $map; MaxCol = $maxCol } }
    }
    throw "Cabecalho nao encontrado (procurado: $($RequiredHeaders -join ', '))"
}

# ============================================================================
# READERS
# ============================================================================
function Read-SistemaFile {
    param($ExcelApp, [string]$Path, [string]$Unidade, [string]$Password = "")
    $ctx = Open-WorkbookRobust -ExcelApp $ExcelApp -Path $Path -Password $Password
    try {
        $ws = $ctx.Workbook.Worksheets.Item(1)
        $hdr = Find-HeaderRow -Worksheet $ws -RequiredHeaders @("dtData", "idVenda", "stFormaPagamento", "Total")
        $lastRow = $ws.UsedRange.Rows.Count
        $rng = $ws.Range($ws.Cells.Item($hdr.Row, 1), $ws.Cells.Item($lastRow, $hdr.MaxCol))
        $arr = $rng.Value2
        $n = $arr.GetLength(0)
        $cData = $hdr.Map["dtdata"]; $cHora = $hdr.Map["horacompleta"]
        $cIdVenda = $hdr.Map["idvenda"]; $cIdAbertura = $hdr.Map["idabertura"]
        $cForma = $hdr.Map["stformapagamento"]; $cTotal = $hdr.Map["total"]
        $cTurno = $hdr.Map["turno"]
        $records = New-Object System.Collections.Generic.List[object]
        for ($r = 2; $r -le $n; $r++) {
            $dataV = $arr[$r, $cData]
            if ($null -eq $dataV -or "$dataV" -eq "") { continue }
            $data = ConvertTo-DateSafe $dataV
            if ($null -eq $data) { continue }
            $hora = ConvertTo-TimeSafe $arr[$r, $cHora]
            $formaRaw = "$($arr[$r, $cForma])".Trim()
            $valor = ConvertTo-DecimalAny $arr[$r, $cTotal]
            $linha = ($r + $hdr.Row - 1)
            $records.Add([PSCustomObject]@{
                Tipo = "Sistema"; Banco = ""; Unidade = $Unidade
                Data = $data; Hora = $hora; DataHora = $data.Add($hora)
                IdVenda = "$($arr[$r, $cIdVenda])"; IdAbertura = "$($arr[$r, $cIdAbertura])"
                Turno = if ($cTurno) { "$($arr[$r, $cTurno])" } else { "" }
                FormaOriginal = $formaRaw
                FormaCanonica = ConvertTo-FormaCanonica -Origem "Sistema" -Raw $formaRaw
                Valor = $valor; Status = "OK"; Efetivada = $true
                Terminal = ""; CodigoAutorizacao = ""; TerminalDisplay = ""; NsuComprovante = ""; CodigoVendaPedido = ""; Referencia = ""
                ArquivoOrigem = [System.IO.Path]::GetFileName($Path)
                LinhaOrigem = $linha
                RID = "SYS-$(Get-UnidadeSlugLower $Unidade)$($data.ToString('dd'))-$linha"
                Usado = $false; RefId = [Guid]::NewGuid().ToString("N")
            }) | Out-Null
        }
        return $records
    } finally { Close-WorkbookCtx -Ctx $ctx }
}

function Read-C6File {
    param($ExcelApp, [string]$Path, [string]$Password = "")
    $ctx = Open-WorkbookRobust -ExcelApp $ExcelApp -Path $Path -Password $Password
    try {
        $ws = $ctx.Workbook.Worksheets.Item(1)
        $hdr = Find-HeaderRow -Worksheet $ws -RequiredHeaders @("Data da venda", "Status da venda", "Valor da venda bruta (R$)", "ID PDC", "Modalidade")
        $lastRow = $ws.UsedRange.Rows.Count
        $rng = $ws.Range($ws.Cells.Item($hdr.Row, 1), $ws.Cells.Item($lastRow, $hdr.MaxCol))
        $arr = $rng.Value2
        $n = $arr.GetLength(0)
        $cData = $hdr.Map["data da venda"]; $cHora = $hdr.Map["hora da venda"]
        $cStatus = $hdr.Map["status da venda"]; $cValor = $hdr.Map["valor da venda bruta (r$)"]
        $cModalidade = $hdr.Map["modalidade"]; $cPdc = $hdr.Map["id pdc"]
        $cCodVenda = $hdr.Map["código da venda"]; $cCodAut = $hdr.Map["código autorização"]
        $cSerie = $hdr.Map["nº série maquininha"]; $cReferencia = $hdr.Map["referência"]; $cNsu = $hdr.Map["nsu"]
        $records = New-Object System.Collections.Generic.List[object]
        for ($r = 2; $r -le $n; $r++) {
            $dataV = $arr[$r, $cData]
            if ($null -eq $dataV -or "$dataV" -eq "") { continue }
            $data = ConvertTo-DateSafe $dataV
            if ($null -eq $data) { continue }
            $hora = ConvertTo-TimeSafe $arr[$r, $cHora]
            $status = "$($arr[$r, $cStatus])".Trim()
            $valor = ConvertTo-DecimalAny $arr[$r, $cValor]
            $pdc = "$($arr[$r, $cPdc])".Trim()
            $modalidade = "$($arr[$r, $cModalidade])".Trim()
            $linha = ($r + $hdr.Row - 1)
            $records.Add([PSCustomObject]@{
                Tipo = "Banco"; Banco = "C6"; Unidade = "?"
                Data = $data; Hora = $hora; DataHora = $data.Add($hora)
                IdVenda = ""; IdAbertura = ""; Turno = ""
                FormaOriginal = $modalidade
                FormaCanonica = ConvertTo-FormaCanonica -Origem "Banco" -Modalidade $modalidade
                Valor = $valor; Status = $status; Efetivada = ($status -eq "Aprovada")
                Terminal = $pdc
                CodigoAutorizacao = if ($cCodAut) { "$($arr[$r, $cCodAut])" } else { "" }
                TerminalDisplay = if ($cSerie) { "$($arr[$r, $cSerie])" } else { $pdc }
                NsuComprovante = if ($cNsu) { "$($arr[$r, $cNsu])" } else { "" }
                CodigoVendaPedido = if ($cCodVenda) { "$($arr[$r, $cCodVenda])" } else { "" }
                Referencia = if ($cReferencia) { "$($arr[$r, $cReferencia])" } else { "" }
                ArquivoOrigem = [System.IO.Path]::GetFileName($Path)
                LinhaOrigem = $linha
                RID = "C6-$linha"
                Usado = $false; RefId = [Guid]::NewGuid().ToString("N")
            }) | Out-Null
        }
        return $records
    } finally { Close-WorkbookCtx -Ctx $ctx }
}

function Read-SicrediFile {
    param($ExcelApp, [string]$Path, [string]$Password = "")
    $ctx = Open-WorkbookRobust -ExcelApp $ExcelApp -Path $Path -Password $Password
    try {
        $ws = $ctx.Workbook.Worksheets.Item(1)
        $hdr = Find-HeaderRow -Worksheet $ws -RequiredHeaders @("Data da venda", "Código do estabelecimento", "Valor bruto transação", "Status", "Modalidade")
        $lastRow = $ws.UsedRange.Rows.Count
        $rng = $ws.Range($ws.Cells.Item($hdr.Row, 1), $ws.Cells.Item($lastRow, $hdr.MaxCol))
        $arr = $rng.Value2
        $n = $arr.GetLength(0)
        $cData = $hdr.Map["data da venda"]; $cHora = $hdr.Map["hora da venda"]
        $cEstab = $hdr.Map["código do estabelecimento"]; $cModalidade = $hdr.Map["modalidade"]
        $cProduto = $hdr.Map["produto"]; $cValor = $hdr.Map["valor bruto transação"]
        $cStatus = $hdr.Map["status"]; $cCodAut = $hdr.Map["código de autorização"]
        $cNumTerminal = $hdr.Map["número do terminal"]; $cComprovante = $hdr.Map["comprovante de venda"]
        $cCodPedido = $hdr.Map["código do pedido"]
        $records = New-Object System.Collections.Generic.List[object]
        for ($r = 2; $r -le $n; $r++) {
            $dataV = $arr[$r, $cData]
            if ($null -eq $dataV -or "$dataV" -eq "") { continue }
            $data = ConvertTo-DateSafe $dataV
            if ($null -eq $data) { continue }
            $hora = ConvertTo-TimeSafe $arr[$r, $cHora]
            $estab = "$($arr[$r, $cEstab])".Trim()
            $modalidade = "$($arr[$r, $cModalidade])".Trim()
            $produto = "$($arr[$r, $cProduto])".Trim()
            $valor = ConvertTo-DecimalAny $arr[$r, $cValor]
            $status = "$($arr[$r, $cStatus])".Trim()
            $linha = ($r + $hdr.Row - 1)
            $records.Add([PSCustomObject]@{
                Tipo = "Banco"; Banco = "Sicredi"; Unidade = "?"
                Data = $data; Hora = $hora; DataHora = $data.Add($hora)
                IdVenda = ""; IdAbertura = ""; Turno = ""
                FormaOriginal = "$modalidade/$produto"
                FormaCanonica = ConvertTo-FormaCanonica -Origem "Banco" -Modalidade $modalidade -Produto $produto
                Valor = $valor; Status = $status; Efetivada = ($status -eq "Aprovada" -or $status -eq "Autorizada")
                Terminal = $estab
                CodigoAutorizacao = if ($cCodAut) { "$($arr[$r, $cCodAut])" } else { "" }
                TerminalDisplay = if ($cNumTerminal) { "$($arr[$r, $cNumTerminal])" } else { $estab }
                NsuComprovante = if ($cComprovante) { "$($arr[$r, $cComprovante])" } else { "" }
                CodigoVendaPedido = if ($cCodPedido) { "$($arr[$r, $cCodPedido])" } else { "" }
                Referencia = ""
                ArquivoOrigem = [System.IO.Path]::GetFileName($Path)
                LinhaOrigem = $linha
                RID = "SICREDI-$linha"
                Usado = $false; RefId = [Guid]::NewGuid().ToString("N")
            }) | Out-Null
        }
        return $records
    } finally { Close-WorkbookCtx -Ctx $ctx }
}

function Apply-UnitMapping {
    param($BancoRecords, [hashtable]$PdcUnidade, [hashtable]$EstabelecimentoUnidade)
    foreach ($rec in $BancoRecords) {
        if ($rec.Banco -eq "C6") {
            $rec.Unidade = if ($PdcUnidade.ContainsKey($rec.Terminal)) { $PdcUnidade[$rec.Terminal] } else { "DESCONHECIDA" }
        } elseif ($rec.Banco -eq "Sicredi") {
            $rec.Unidade = if ($EstabelecimentoUnidade.ContainsKey($rec.Terminal)) { $EstabelecimentoUnidade[$rec.Terminal] } else { "DESCONHECIDA" }
        }
    }
}

function Remove-RegistrosForaDaRegraUnidade {
    # Regra de negocio pedida pelo usuario: a unidade VILA MOURA so concilia a forma VOUCHER -
    # as demais formas (Debito, Credito, PIX, Dinheiro, Conta Assinada...) sao descartadas antes
    # da conciliacao pra essa unidade, tanto do lado sistema quanto do lado banco, como se essa
    # unidade simplesmente nao tivesse essas vendas para fins de conciliacao. Mooca (e qualquer
    # outra unidade) continua sem restricao. Chamar depois de Apply-UnitMapping, ja que o
    # registro de banco so tem Unidade definida a partir dali.
    param($SistemaRecords, $BancoRecords)
    $sistemaFiltrado = New-Object System.Collections.Generic.List[object]
    foreach ($r in $SistemaRecords) {
        if ($r.Unidade -eq "VILA MOURA" -and $r.FormaCanonica -ne "VOUCHER") { continue }
        $sistemaFiltrado.Add($r) | Out-Null
    }
    $bancoFiltrado = New-Object System.Collections.Generic.List[object]
    foreach ($r in $BancoRecords) {
        if ($r.Unidade -eq "VILA MOURA" -and $r.FormaCanonica -ne "VOUCHER") { continue }
        $bancoFiltrado.Add($r) | Out-Null
    }
    return [PSCustomObject]@{
        Sistema = $sistemaFiltrado; Banco = $bancoFiltrado
        DescartadosSistema = ($SistemaRecords.Count - $sistemaFiltrado.Count)
        DescartadosBanco = ($BancoRecords.Count - $bancoFiltrado.Count)
    }
}

# ============================================================================
# MATCHING ENGINE
# ============================================================================
function New-Grupo {
    param([string]$Tipo, $SistemaRecs, $BancoRecs, [string]$Observacao = "")
    $sTotal = ($SistemaRecs | Measure-Object -Property Valor -Sum).Sum
    if ($null -eq $sTotal) { $sTotal = 0.0 }
    $bTotal = ($BancoRecs | Measure-Object -Property Valor -Sum).Sum
    if ($null -eq $bTotal) { $bTotal = 0.0 }
    [PSCustomObject]@{
        GrupoId = [Guid]::NewGuid().ToString("N").Substring(0, 8)
        Tipo = $Tipo
        Unidade = @($SistemaRecs + $BancoRecs | Where-Object { $_ } | Select-Object -First 1).Unidade
        Data = @($SistemaRecs + $BancoRecs | Where-Object { $_ } | Select-Object -First 1).Data
        SistemaRecs = @($SistemaRecs)
        BancoRecs = @($BancoRecs)
        TotalSistema = $sTotal
        TotalBanco = $bTotal
        Diferenca = [Math]::Round($bTotal - $sTotal, 2)
        Observacao = $Observacao
    }
}

function Get-Combinacoes {
    param([int[]]$Arr, [int]$K)
    if ($K -eq 0) { return , @() }
    if ($Arr.Count -eq 0) { return @() }
    $head = $Arr[0]
    $rest = if ($Arr.Count -gt 1) { $Arr[1..($Arr.Count - 1)] } else { @() }
    $withHead = Get-Combinacoes -Arr $rest -K ($K - 1) | ForEach-Object { , (@($head) + $_) }
    $withoutHead = Get-Combinacoes -Arr $rest -K $K
    return @($withHead) + @($withoutHead)
}

function Greedy-Match {
    # Gera todos os pares candidatos que atendem aos criterios, ordena por proximidade
    # (valor, depois tempo) e faz uma unica varredura gulosa atribuindo pares unicos.
    # Evita refazer a busca do zero a cada correspondencia encontrada (o que tornava o
    # algoritmo anterior O(numero_de_matches * tamanho_do_grupo) e muito lento em bases grandes).
    param($SisList, $BkList, [double]$MaxValueDiff, [double]$MinMinutes, [double]$MaxMinutes, [bool]$SameForma, [bool]$RequireDiffForma = $false)
    $cands = New-Object System.Collections.Generic.List[object]
    foreach ($sr in $SisList) {
        if ($sr.Usado) { continue }
        foreach ($br in $BkList) {
            if ($br.Usado) { continue }
            if ($SameForma -and $sr.FormaCanonica -ne $br.FormaCanonica) { continue }
            if ($RequireDiffForma -and $sr.FormaCanonica -eq $br.FormaCanonica) { continue }
            $vdiff = [Math]::Abs($sr.Valor - $br.Valor)
            if ($vdiff -gt $MaxValueDiff) { continue }
            $diffMin = [Math]::Abs(($sr.DataHora - $br.DataHora).TotalMinutes)
            if ($diffMin -lt $MinMinutes -or $diffMin -gt $MaxMinutes) { continue }
            $score = $vdiff * 100000.0 + $diffMin
            $cands.Add([PSCustomObject]@{ S = $sr; B = $br; Score = $score }) | Out-Null
        }
    }
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($c in ($cands | Sort-Object Score)) {
        if (-not $c.S.Usado -and -not $c.B.Usado) {
            $c.S.Usado = $true; $c.B.Usado = $true
            $results.Add($c) | Out-Null
        }
    }
    return $results
}

function Invoke-Reconciliacao {
    param($SistemaRecords, $BancoRecords, [scriptblock]$ProgressCallback = $null)

    foreach ($r in $SistemaRecords) { $r.Usado = $false }
    foreach ($r in $BancoRecords) { $r.Usado = $false }

    $grupos = New-Object System.Collections.Generic.List[object]

    $bancoEfetivado = @($BancoRecords | Where-Object { $_.Efetivada -and $_.Unidade -ne "DESCONHECIDA" })

    $unidades = @($SistemaRecords.Unidade + $bancoEfetivado.Unidade | Sort-Object -Unique)
    $datas = @($SistemaRecords.Data + $bancoEfetivado.Data | Sort-Object -Unique)

    # indices por (unidade, data) para nao varrer a base inteira a cada bucket
    $sisIdx = @{}
    foreach ($r in $SistemaRecords) {
        $k = "$($r.Unidade)|$($r.Data.Ticks)"
        if (-not $sisIdx.ContainsKey($k)) { $sisIdx[$k] = New-Object System.Collections.Generic.List[object] }
        $sisIdx[$k].Add($r) | Out-Null
    }
    $bkIdx = @{}
    foreach ($r in $bancoEfetivado) {
        $k = "$($r.Unidade)|$($r.Data.Ticks)"
        if (-not $bkIdx.ContainsKey($k)) { $bkIdx[$k] = New-Object System.Collections.Generic.List[object] }
        $bkIdx[$k].Add($r) | Out-Null
    }

    $formasEletronicas = @("DÉBITO", "CRÉDITO", "PIX", "VOUCHER")

    foreach ($un in $unidades) {
        foreach ($dt in $datas) {
            $k = "$un|$($dt.Ticks)"
            if (-not $sisIdx.ContainsKey($k) -or -not $bkIdx.ContainsKey($k)) { continue }
            $sisBucket = $sisIdx[$k]
            $bkBucket = $bkIdx[$k]

            foreach ($m in (Greedy-Match $sisBucket $bkBucket 0.005 0 2 $true)) {
                $grupos.Add((New-Grupo "Forte (valor exato, ate 2 min)" @($m.S) @($m.B))) | Out-Null
            }
            foreach ($m in (Greedy-Match $sisBucket $bkBucket 0.005 2.0001 10 $true)) {
                $grupos.Add((New-Grupo "Possivel (valor exato, 2-10 min - revisar)" @($m.S) @($m.B))) | Out-Null
            }
            foreach ($m in (Greedy-Match $sisBucket $bkBucket 1.00 0 10 $true)) {
                $grupos.Add((New-Grupo "Pequena diferenca de valor (ate R`$1,00) - investigar" @($m.S) @($m.B))) | Out-Null
            }
            foreach ($m in (Greedy-Match $sisBucket $bkBucket 0.005 0 2 $false $true)) {
                $obs = "Sistema lancou como $($m.S.FormaCanonica), banco confirma $($m.B.FormaCanonica)"
                $grupos.Add((New-Grupo "Troca de forma" @($m.S) @($m.B) $obs)) | Out-Null
            }
        }
    }

    # PASS 5: pagamentos divididos (1 sistema x N banco, mesma unidade/data, janela de 20 min)
    # restrito a formas eletronicas - dinheiro/conta nunca aparecem no banco
    foreach ($un in $unidades) {
        foreach ($dt in $datas) {
            $k = "$un|$($dt.Ticks)"
            if (-not $sisIdx.ContainsKey($k) -or -not $bkIdx.ContainsKey($k)) { continue }
            $sisLeft = @($sisIdx[$k] | Where-Object { -not $_.Usado -and $formasEletronicas -contains $_.FormaCanonica } | Sort-Object Valor -Descending)
            $bkBucketAll = $bkIdx[$k]
            foreach ($sr in $sisLeft) {
                if ($sr.Usado) { continue }
                $cands = @($bkBucketAll | Where-Object { -not $_.Usado -and [Math]::Abs(($_.DataHora - $sr.DataHora).TotalMinutes) -le 20 } | Sort-Object DataHora)
                if ($cands.Count -lt 2 -or $cands.Count -gt 6) { continue }
                $found = $null
                for ($kk = 2; $kk -le [Math]::Min(5, $cands.Count) -and -not $found; $kk++) {
                    $combos = Get-Combinacoes -Arr @(0..($cands.Count - 1)) -K $kk
                    foreach ($c in $combos) {
                        $sum = 0.0
                        foreach ($idx in $c) { $sum += $cands[$idx].Valor }
                        if ([Math]::Abs($sum - $sr.Valor) -lt 0.02) { $found = $c; break }
                    }
                }
                if ($found) {
                    $sr.Usado = $true
                    $picked = @()
                    foreach ($idx in $found) { $cands[$idx].Usado = $true; $picked += $cands[$idx] }
                    $grupos.Add((New-Grupo "Pagamento dividido" @($sr) $picked)) | Out-Null
                }
            }
        }
    }

    # PASS 6: outra unidade (fallback) - mesma data, valor exato, <=5min
    $sobraSisGlobal = @($SistemaRecords | Where-Object { -not $_.Usado })
    $sobraBkGlobal = @($bancoEfetivado | Where-Object { -not $_.Usado })
    $candsOutraUnidade = New-Object System.Collections.Generic.List[object]
    foreach ($sr in $sobraSisGlobal) {
        foreach ($br in $sobraBkGlobal) {
            if ($sr.Unidade -eq $br.Unidade -or $sr.Data -ne $br.Data) { continue }
            $vdiff = [Math]::Abs($sr.Valor - $br.Valor)
            if ($vdiff -gt 0.005) { continue }
            $diffMin = [Math]::Abs(($sr.DataHora - $br.DataHora).TotalMinutes)
            if ($diffMin -gt 5) { continue }
            $candsOutraUnidade.Add([PSCustomObject]@{ S = $sr; B = $br; Score = $diffMin }) | Out-Null
        }
    }
    foreach ($c in ($candsOutraUnidade | Sort-Object Score)) {
        if (-not $c.S.Usado -and -not $c.B.Usado) {
            $c.S.Usado = $true; $c.B.Usado = $true
            $obs = "ATENCAO: venda do sistema ($($c.S.Unidade)) casou com aprovacao bancaria de outra unidade ($($c.B.Unidade)) - conferir mapeamento de terminal"
            $grupos.Add((New-Grupo "Correspondencia em outra unidade" @($c.S) @($c.B) $obs)) | Out-Null
        }
    }

    # RECUSAS: para vendas do sistema ainda sem par (formas eletronicas), procurar tentativa
    # recusada compativel (apenas anota - nao marca como usado, pois recusa nao comprova recebimento)
    $bancoNaoEfetivado = @($BancoRecords | Where-Object { -not $_.Efetivada })
    $sobrasSistema = @($SistemaRecords | Where-Object { -not $_.Usado })
    $recusasRelacionadas = New-Object System.Collections.Generic.List[object]
    $sobrasSistemaEletronicas = @($sobrasSistema | Where-Object { $formasEletronicas -contains $_.FormaCanonica })
    foreach ($sr in $sobrasSistemaEletronicas) {
        $cand = $bancoNaoEfetivado | Where-Object {
            $_.Unidade -eq $sr.Unidade -and $_.Data -eq $sr.Data -and [Math]::Abs($_.Valor - $sr.Valor) -lt 0.005 -and [Math]::Abs(($_.DataHora - $sr.DataHora).TotalMinutes) -le 15
        } | Sort-Object { [Math]::Abs(($_.DataHora - $sr.DataHora).TotalMinutes) } | Select-Object -First 1
        if ($cand) {
            $recusasRelacionadas.Add([PSCustomObject]@{ Sistema = $sr; TentativaRecusada = $cand }) | Out-Null
        }
    }

    $sobrasSistemaFinal = $sobrasSistema
    $sobrasBancoFinal = @($bancoEfetivado | Where-Object { -not $_.Usado })
    $bancoDesconhecido = $BancoRecords | Where-Object { $_.Unidade -eq "DESCONHECIDA" }

    return [PSCustomObject]@{
        Grupos = $grupos
        SobrasSistema = $sobrasSistemaFinal
        SobrasBanco = $sobrasBancoFinal
        Recusas = $bancoNaoEfetivado
        RecusasRelacionadas = $recusasRelacionadas
        BancoDesconhecido = $bancoDesconhecido
    }
}

function Compute-ResumoFinal {
    # Monta o Resumo por Unidade/Data/Forma e o Resumo_Diario no formato do modelo de referencia:
    # Sistema original -> Reclassificacao -> Ajuste centavos -> Sistema ajustado, comparado a C6/Sicredi brutos.
    param($SistemaRecords, $BancoRecords, $Grupos)

    $formasEletronicas = @("DÉBITO", "CRÉDITO", "PIX", "VOUCHER")
    $bancoEfetivado = @($BancoRecords | Where-Object { $_.Efetivada -and $_.Unidade -ne "?" -and $_.Unidade -ne "DESCONHECIDA" -and $formasEletronicas -contains $_.FormaCanonica })
    $sistemaEletronico = @($SistemaRecords | Where-Object { $formasEletronicas -contains $_.FormaCanonica })

    $buckets = @{}
    function Get-BucketRF {
        param($Unidade, $Data, $Forma)
        $k = "$Unidade|$($Data.ToString('yyyy-MM-dd'))|$Forma"
        if (-not $buckets.ContainsKey($k)) {
            $buckets[$k] = [PSCustomObject]@{
                Unidade = $Unidade; Data = $Data; Forma = $Forma
                SistemaOriginal = 0.0; Reclassificacao = 0.0; AjusteCentavos = 0.0
                C6Bruto = 0.0; SicrediBruto = 0.0
            }
        }
        return $buckets[$k]
    }

    foreach ($r in $sistemaEletronico) { (Get-BucketRF $r.Unidade $r.Data $r.FormaCanonica).SistemaOriginal += $r.Valor }
    foreach ($r in $bancoEfetivado) {
        $b = Get-BucketRF $r.Unidade $r.Data $r.FormaCanonica
        if ($r.Banco -eq "C6") { $b.C6Bruto += $r.Valor } else { $b.SicrediBruto += $r.Valor }
    }

    foreach ($g in $Grupos) {
        if ($g.SistemaRecs.Count -ne 1) { continue }
        $sr = $g.SistemaRecs[0]
        if ($formasEletronicas -notcontains $sr.FormaCanonica) { continue }

        if ($g.Tipo -like "Pequena diferenca*" -and $g.BancoRecs.Count -eq 1) {
            $br = $g.BancoRecs[0]
            (Get-BucketRF $sr.Unidade $sr.Data $sr.FormaCanonica).AjusteCentavos += [Math]::Round($br.Valor - $sr.Valor, 2)
            continue
        }

        foreach ($grp in ($g.BancoRecs | Group-Object FormaCanonica)) {
            if ($grp.Name -eq $sr.FormaCanonica) { continue }
            $soma = ($grp.Group | Measure-Object -Property Valor -Sum).Sum
            (Get-BucketRF $sr.Unidade $sr.Data $sr.FormaCanonica).Reclassificacao -= $soma
            (Get-BucketRF $sr.Unidade $sr.Data $grp.Name).Reclassificacao += $soma
        }
    }

    $resumo = New-Object System.Collections.Generic.List[object]
    foreach ($b in $buckets.Values) {
        $sistemaAjustado = [Math]::Round($b.SistemaOriginal + $b.Reclassificacao + $b.AjusteCentavos, 2)
        $bancosTotal = [Math]::Round($b.C6Bruto + $b.SicrediBruto, 2)
        $saldoOriginal = [Math]::Round($bancosTotal - $b.SistemaOriginal, 2)
        $saldoAjustado = [Math]::Round($bancosTotal - $sistemaAjustado, 2)
        $status = "OK"; if ([Math]::Abs($saldoAjustado) -ge 0.01) { $status = "DIVERGÊNCIA" }
        $resumo.Add([PSCustomObject]@{
            Unidade = $b.Unidade; Data = $b.Data; Forma = $b.Forma
            SistemaOriginal = [Math]::Round($b.SistemaOriginal, 2); Reclassificacao = [Math]::Round($b.Reclassificacao, 2)
            AjusteCentavos = [Math]::Round($b.AjusteCentavos, 2); SistemaAjustado = $sistemaAjustado
            C6Bruto = [Math]::Round($b.C6Bruto, 2); SicrediBruto = [Math]::Round($b.SicrediBruto, 2); BancosTotal = $bancosTotal
            SaldoOriginal = $saldoOriginal; SaldoAjustado = $saldoAjustado; Status = $status
            IdSaldo = "$(Get-UnidadeSlugUpper $b.Unidade)_$($b.Data.ToString('yyyyMMdd'))_$($b.Forma)"
        }) | Out-Null
    }
    $resumo = @($resumo | Sort-Object Unidade, Data, Forma)

    $diarios = @{}
    foreach ($row in $resumo) {
        $k = "$($row.Unidade)|$($row.Data.ToString('yyyy-MM-dd'))"
        if (-not $diarios.ContainsKey($k)) {
            $diarios[$k] = [PSCustomObject]@{ Unidade = $row.Unidade; Data = $row.Data; SistemaOriginal = 0.0; SistemaAjustado = 0.0; C6Bruto = 0.0; SicrediBruto = 0.0 }
        }
        $diarios[$k].SistemaOriginal += $row.SistemaOriginal
        $diarios[$k].SistemaAjustado += $row.SistemaAjustado
        $diarios[$k].C6Bruto += $row.C6Bruto
        $diarios[$k].SicrediBruto += $row.SicrediBruto
    }
    $resumoDiario = New-Object System.Collections.Generic.List[object]
    foreach ($d in $diarios.Values) {
        $bancosTotal = [Math]::Round($d.C6Bruto + $d.SicrediBruto, 2)
        $saldoOriginal = [Math]::Round($bancosTotal - $d.SistemaOriginal, 2)
        $saldoAjustado = [Math]::Round($bancosTotal - $d.SistemaAjustado, 2)
        $status = "OK"; if ([Math]::Abs($saldoAjustado) -ge 0.01) { $status = "DIVERGÊNCIA" }
        $resumoDiario.Add([PSCustomObject]@{
            Unidade = $d.Unidade; Data = $d.Data
            SistemaOriginal = [Math]::Round($d.SistemaOriginal, 2); SistemaAjustado = [Math]::Round($d.SistemaAjustado, 2)
            C6Bruto = [Math]::Round($d.C6Bruto, 2); SicrediBruto = [Math]::Round($d.SicrediBruto, 2); BancosTotal = $bancosTotal
            SaldoOriginal = $saldoOriginal; SaldoAjustado = $saldoAjustado; Status = $status
        }) | Out-Null
    }
    $resumoDiario = @($resumoDiario | Sort-Object Unidade, Data)

    return [PSCustomObject]@{ Resumo = $resumo; ResumoDiario = $resumoDiario }
}

function Build-DiferencasDetalhadas {
    # Lista, linha a linha, os itens que explicam o saldo de cada ID Saldo com divergencia:
    # pares batidos por tolerancia (VALOR DIVERGENTE), sobras do banco (SOMENTE NO BANCO)
    # e sobras do sistema (SOMENTE NO SISTEMA).
    param($Resumo, $Grupos, $SobrasSistema, $SobrasBanco)

    $formasEletronicas = @("DÉBITO", "CRÉDITO", "PIX", "VOUCHER")
    $porGrupo = @{}
    foreach ($row in $Resumo) { $porGrupo[$row.IdSaldo] = $row }

    $itens = New-Object System.Collections.Generic.List[object]

    foreach ($g in ($Grupos | Where-Object { $_.Tipo -like "Pequena diferenca*" })) {
        if ($g.SistemaRecs.Count -ne 1 -or $g.BancoRecs.Count -ne 1) { continue }
        $sr = $g.SistemaRecs[0]; $br = $g.BancoRecs[0]
        if ($formasEletronicas -notcontains $sr.FormaCanonica) { continue }
        $segs = [Math]::Round([Math]::Abs(($sr.DataHora - $br.DataHora).TotalSeconds))
        $itens.Add([PSCustomObject]@{
            IdSaldo = "$(Get-UnidadeSlugUpper $sr.Unidade)_$($sr.Data.ToString('yyyyMMdd'))_$($sr.FormaCanonica)"
            Unidade = $sr.Unidade; Data = $sr.Data; Forma = $sr.FormaCanonica; Tipo = "VALOR DIVERGENTE"
            HoraSis = $sr.Hora; ValorSis = $sr.Valor; IdVendaSis = $sr.IdVenda
            Banco = $br.Banco; HoraBk = $br.Hora; ValorBk = $br.Valor
            Autorizacao = $br.CodigoAutorizacao; Nsu = $br.NsuComprovante; Terminal = $br.TerminalDisplay
            Obs = "Horarios proximos (${segs}s), mas valores diferentes."
        }) | Out-Null
    }
    foreach ($br in ($SobrasBanco | Where-Object { $formasEletronicas -contains $_.FormaCanonica })) {
        $itens.Add([PSCustomObject]@{
            IdSaldo = "$(Get-UnidadeSlugUpper $br.Unidade)_$($br.Data.ToString('yyyyMMdd'))_$($br.FormaCanonica)"
            Unidade = $br.Unidade; Data = $br.Data; Forma = $br.FormaCanonica; Tipo = "SOMENTE NO BANCO"
            HoraSis = $null; ValorSis = 0.0; IdVendaSis = ""
            Banco = $br.Banco; HoraBk = $br.Hora; ValorBk = $br.Valor
            Autorizacao = $br.CodigoAutorizacao; Nsu = $br.NsuComprovante; Terminal = $br.TerminalDisplay
            Obs = "Sem correspondente identificado no fechamento do sistema."
        }) | Out-Null
    }
    foreach ($sr in ($SobrasSistema | Where-Object { $formasEletronicas -contains $_.FormaCanonica })) {
        $itens.Add([PSCustomObject]@{
            IdSaldo = "$(Get-UnidadeSlugUpper $sr.Unidade)_$($sr.Data.ToString('yyyyMMdd'))_$($sr.FormaCanonica)"
            Unidade = $sr.Unidade; Data = $sr.Data; Forma = $sr.FormaCanonica; Tipo = "SOMENTE NO SISTEMA"
            HoraSis = $sr.Hora; ValorSis = $sr.Valor; IdVendaSis = $sr.IdVenda
            Banco = ""; HoraBk = $null; ValorBk = 0.0
            Autorizacao = ""; Nsu = ""; Terminal = ""
            Obs = "Sem correspondente identificado nos relatorios bancarios."
        }) | Out-Null
    }

    # Trocas de forma (ex.: venda lancada como DEBITO no sistema, aprovada como CREDITO no
    # banco): a reclassificacao ja fica detalhada na aba Ajustes_Reclassif, mas sem entrada
    # aqui a diferenca "some" - a forma original fica com sobra de sistema sem explicacao
    # visivel e a forma de destino fica com sobra de banco sem explicacao visivel. Repete a
    # mesma logica de deteccao de troca do Build-AjustesReclassif, gerando uma linha em cada
    # lado (ID Saldo de origem e de destino) marcada com Tipo="TROCA DE FORMA" pra aparecer
    # destacada na planilha.
    foreach ($g in $Grupos) {
        if ($g.SistemaRecs.Count -ne 1 -or $g.Tipo -like "Pequena diferenca*") { continue }
        $sr = $g.SistemaRecs[0]
        if ($formasEletronicas -notcontains $sr.FormaCanonica) { continue }
        $porForma = @($g.BancoRecs | Group-Object FormaCanonica)
        $temTroca = @($porForma | Where-Object { $_.Name -ne $sr.FormaCanonica }).Count -gt 0
        if (-not $temTroca) { continue }

        $composicaoTexto = (($porForma | ForEach-Object { "$($_.Name) R`$$(Format-ValorPonto (($_.Group | Measure-Object -Property Valor -Sum).Sum))" }) -join ", ")
        $bancoNomes = (($g.BancoRecs | Select-Object -ExpandProperty Banco -Unique) -join "/")
        $obsTroca = "Venda lancada como $($sr.FormaCanonica) no sistema, aprovada como $composicaoTexto no banco (ver aba Ajustes_Reclassif)."

        $itens.Add([PSCustomObject]@{
            IdSaldo = "$(Get-UnidadeSlugUpper $sr.Unidade)_$($sr.Data.ToString('yyyyMMdd'))_$($sr.FormaCanonica)"
            Unidade = $sr.Unidade; Data = $sr.Data; Forma = $sr.FormaCanonica; Tipo = "TROCA DE FORMA"
            HoraSis = $sr.Hora; ValorSis = $sr.Valor; IdVendaSis = $sr.IdVenda
            Banco = $bancoNomes; HoraBk = $null; ValorBk = 0.0
            Autorizacao = ""; Nsu = ""; Terminal = ""
            Obs = $obsTroca
        }) | Out-Null

        foreach ($grp in $porForma) {
            if ($grp.Name -eq $sr.FormaCanonica) { continue }
            $soma = [Math]::Round((($grp.Group | Measure-Object -Property Valor -Sum).Sum), 2)
            $primeiro = $grp.Group[0]
            $itens.Add([PSCustomObject]@{
                IdSaldo = "$(Get-UnidadeSlugUpper $sr.Unidade)_$($sr.Data.ToString('yyyyMMdd'))_$($grp.Name)"
                Unidade = $sr.Unidade; Data = $sr.Data; Forma = $grp.Name; Tipo = "TROCA DE FORMA"
                HoraSis = $null; ValorSis = 0.0; IdVendaSis = $sr.IdVenda
                Banco = $bancoNomes; HoraBk = $primeiro.Hora; ValorBk = $soma
                Autorizacao = $primeiro.CodigoAutorizacao; Nsu = $primeiro.NsuComprovante; Terminal = $primeiro.TerminalDisplay
                Obs = $obsTroca
            }) | Out-Null
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($it in ($itens | Sort-Object Unidade, Data, Forma, Tipo)) {
        $saldoAjustado = 0.0
        if ($porGrupo.ContainsKey($it.IdSaldo)) { $saldoAjustado = $porGrupo[$it.IdSaldo].SaldoAjustado }
        $saldoGrupo = [Math]::Round(-$saldoAjustado, 2)
        $impacto = [Math]::Round($it.ValorSis - $it.ValorBk, 2)
        $rows.Add(@(
            $it.IdSaldo, $it.Unidade, $it.Data, $it.Forma, $it.Tipo,
            (Format-HoraBR $it.HoraSis), $it.ValorSis, $it.IdVendaSis,
            $it.Banco, (Format-HoraBR $it.HoraBk), $it.ValorBk,
            $it.Autorizacao, $it.Nsu, $it.Terminal,
            $impacto, $saldoGrupo, $it.Obs
        )) | Out-Null
    }
    return $rows
}

function Build-AjustesReclassif {
    # Uma linha por lado de cada reclassificacao (retira da forma original, acrescenta na forma do banco),
    # mais uma linha por batimento de centavos - com rastreabilidade completa (RID sistema/banco).
    param($Grupos)

    $formasEletronicas = @("DÉBITO", "CRÉDITO", "PIX", "VOUCHER")
    $itens = New-Object System.Collections.Generic.List[object]

    foreach ($g in $Grupos) {
        if ($g.SistemaRecs.Count -ne 1) { continue }
        $sr = $g.SistemaRecs[0]
        if ($formasEletronicas -notcontains $sr.FormaCanonica) { continue }

        if ($g.Tipo -like "Pequena diferenca*" -and $g.BancoRecs.Count -eq 1) {
            $br = $g.BancoRecs[0]
            $residual = [Math]::Round($br.Valor - $sr.Valor, 2)
            if ([Math]::Abs($residual) -lt 0.001) { continue }
            $desc = "Batimento por tolerancia de centavos: Sistema R`$$(Format-ValorPonto $sr.Valor) x Banco R`$$(Format-ValorPonto $br.Valor)"
            $itens.Add([PSCustomObject]@{
                Unidade = $sr.Unidade; Data = $sr.Data; Forma = $sr.FormaCanonica; Tipo = "CENTAVOS"; Impacto = $residual; Desc = $desc
                IdVenda = $sr.IdVenda; RidSis = $sr.RID; RidBanco = $br.RID; HoraSis = $sr.Hora; HoraBanco = (Format-HoraBR $br.Hora); Banco = $br.Banco
            }) | Out-Null
            continue
        }

        $porForma = @($g.BancoRecs | Group-Object FormaCanonica)
        $temTroca = @($porForma | Where-Object { $_.Name -ne $sr.FormaCanonica }).Count -gt 0
        if (-not $temTroca) { continue }

        $ehAgregado = $g.BancoRecs.Count -gt 1
        $composicaoTexto = (($porForma | ForEach-Object { "$($_.Name) R`$$(Format-ValorPonto (($_.Group | Measure-Object -Property Valor -Sum).Sum))" }) -join ", ")
        $prefixo = "TROCA_FORMA"; if ($ehAgregado) { $prefixo = "AGREGADO_TROCA_FORMA" }
        $desc = "${prefixo}: sistema [$($sr.FormaCanonica) R`$$(Format-ValorPonto $sr.Valor)] -> banco [$composicaoTexto]"
        $bancoNomes = (($g.BancoRecs | Select-Object -ExpandProperty Banco -Unique) -join "/")

        foreach ($grp in $porForma) {
            if ($grp.Name -eq $sr.FormaCanonica) { continue }
            $soma = [Math]::Round((($grp.Group | Measure-Object -Property Valor -Sum).Sum), 2)
            $ridBancoSub = (($grp.Group | ForEach-Object { $_.RID }) -join ", ")
            $horaBancoSub = (($grp.Group | ForEach-Object { Format-HoraBR $_.Hora }) -join ", ")

            $itens.Add([PSCustomObject]@{
                Unidade = $sr.Unidade; Data = $sr.Data; Forma = $sr.FormaCanonica; Tipo = "RECLASSIFICAÇÃO"; Impacto = (-$soma); Desc = $desc
                IdVenda = $sr.IdVenda; RidSis = $sr.RID; RidBanco = $ridBancoSub; HoraSis = $sr.Hora; HoraBanco = $horaBancoSub; Banco = $bancoNomes
            }) | Out-Null
            $itens.Add([PSCustomObject]@{
                Unidade = $sr.Unidade; Data = $sr.Data; Forma = $grp.Name; Tipo = "RECLASSIFICAÇÃO"; Impacto = $soma; Desc = $desc
                IdVenda = $sr.IdVenda; RidSis = $sr.RID; RidBanco = $ridBancoSub; HoraSis = $sr.Hora; HoraBanco = $horaBancoSub; Banco = $bancoNomes
            }) | Out-Null
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($it in ($itens | Sort-Object Unidade, Data, Forma)) {
        $rows.Add(@(
            $it.Unidade, $it.Data, $it.Forma, $it.Tipo, $it.Impacto, $it.Desc,
            $it.IdVenda, $it.RidSis, $it.RidBanco, (Format-HoraBR $it.HoraSis), $it.HoraBanco, $it.Banco
        )) | Out-Null
    }
    return $rows
}

# ============================================================================
# EXPORTACAO DO RELATORIO
# ============================================================================
function Convert-HexToOle {
    # Converte "#RRGGBB" para o Long BGR que o Excel/COM espera em .Interior.Color / .Font.Color
    param([string]$Hex)
    $h = $Hex.TrimStart("#")
    $r = [Convert]::ToInt32($h.Substring(0,2), 16)
    $g = [Convert]::ToInt32($h.Substring(2,2), 16)
    $b = [Convert]::ToInt32($h.Substring(4,2), 16)
    return $r -bor ($g -shl 8) -bor ($b -shl 16)
}

function Write-SheetFromRows {
    # DateColIndexes: colunas (1-based) que recebem um valor de data real (DateTime) na
    # linha - aplicamos o formato "dd/mm/yyyy" explicitamente apos escrever, para o Excel
    # nao exibir no formato da maquina local (ex.: mes/dia americano).
    # CurrencyColIndexes: colunas com valores monetarios (formato "R$ 0,00", negativo em vermelho).
    param(
        $Workbook, [string]$SheetName, [string[]]$Headers, [System.Collections.IList]$Rows,
        [int[]]$DateColIndexes = @(), [int[]]$CurrencyColIndexes = @(),
        # brand-700 do design system - cabecalho de tabela igual ao topo de tela, unico em
        # todas as abas (nao mais uma cor diferente por planilha).
        [string]$HeaderColorHex = "#143D2B"
    )
    $ws = $Workbook.Worksheets.Add()
    $ws.Name = $SheetName.Substring(0, [Math]::Min(31, $SheetName.Length))
    $nCols = $Headers.Count
    $nRows = $Rows.Count + 1
    $arr = New-Object 'object[,]' $nRows, $nCols
    for ($c = 0; $c -lt $nCols; $c++) { $arr[0, $c] = $Headers[$c] }
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $row = $Rows[$r]
        for ($c = 0; $c -lt $nCols; $c++) {
            $v = $row[$c]
            $val = if ($null -eq $v) { "" } else { $v }
            $arr[($r + 1), $c] = $val
        }
    }
    $rng = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item([Math]::Max($nRows,1), $nCols))
    $rng.Font.Name = "Calibri"; $rng.Font.Size = 11
    $rng.Value2 = $arr
    $headerRng = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, $nCols))
    $headerRng.Font.Bold = $true
    $headerRng.Font.Color = Convert-HexToOle "#FFFFFF"
    $headerRng.Interior.Color = Convert-HexToOle $HeaderColorHex
    if ($nRows -gt 1) {
        Set-CurrencyFormat -Ws $ws -ColIndexes $CurrencyColIndexes -FirstRow 2 -LastRow $nRows
        foreach ($dc in $DateColIndexes) { $ws.Range($ws.Cells.Item(2, $dc), $ws.Cells.Item($nRows, $dc)).NumberFormatLocal = $Script:FormatoData }
    }
    try { $ws.Columns.AutoFit() | Out-Null } catch {}
    return $ws
}

function Format-DataBR { param($d) if ($d) { $d.ToString("dd/MM/yyyy") } else { "" } }
function Format-HoraBR { param($t) if ($t) { $t.ToString("hh\:mm\:ss") } else { "" } }

$Script:FormatoMoeda = '"R$ "#.##0,00;[Vermelho]"-R$ "#.##0,00'
$Script:FormatoMoedaSimples = '"R$ "#.##0,00'
$Script:FormatoData = "dd/mm/aaaa"

function Set-CurrencyFormat {
    param($Ws, [int[]]$ColIndexes, [int]$FirstRow, [int]$LastRow, [string]$Format = $Script:FormatoMoeda)
    if ($LastRow -lt $FirstRow) { return }
    foreach ($ci in $ColIndexes) {
        $Ws.Range($Ws.Cells.Item($FirstRow, $ci), $Ws.Cells.Item($LastRow, $ci)).NumberFormat = $Format
    }
}

function Write-TitledSheet {
    # Cria uma aba com titulo + legenda (linhas mescladas coloridas), linha em branco,
    # cabecalho de tabela, dados e uma linha de total - no layout exato do modelo de
    # referencia (Resumo / Resumo_Diario).
    param(
        $Workbook, [string]$SheetName, [string[]]$TitleLines, [string[]]$Headers, [System.Collections.IList]$Rows,
        [object[]]$TotalRow = $null, [int[]]$DateColIndexes = @(), [int[]]$CurrencyColIndexes = @(),
        # brand-700 (titulo/cabecalho) e brand-100 (linha de total, com texto em brand-700) do
        # design system - mesmo par de cores em toda aba, nao mais uma paleta por planilha.
        [string]$TitleColorHex = "#143D2B", [string]$HeaderColorHex = "#143D2B", [string]$TotalColorHex = "#E3F2E8"
    )
    $ws = $Workbook.Worksheets.Add()
    $ws.Name = $SheetName.Substring(0, [Math]::Min(31, $SheetName.Length))
    $nCols = $Headers.Count
    $headerRowIdx = $TitleLines.Count + 2
    $totalExtra = 0; if ($TotalRow) { $totalExtra = 1 }
    $nRows = $headerRowIdx + $Rows.Count + $totalExtra
    $arr = New-Object 'object[,]' $nRows, $nCols
    for ($t = 0; $t -lt $TitleLines.Count; $t++) { $arr[$t, 0] = $TitleLines[$t] }
    for ($c = 0; $c -lt $nCols; $c++) { $arr[($headerRowIdx - 1), $c] = $Headers[$c] }
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $row = $Rows[$r]
        for ($c = 0; $c -lt $nCols; $c++) {
            $v = $row[$c]
            $val = if ($null -eq $v) { "" } else { $v }
            $arr[($headerRowIdx + $r), $c] = $val
        }
    }
    if ($TotalRow) {
        for ($c = 0; $c -lt $nCols; $c++) {
            $v = $TotalRow[$c]
            $val = if ($null -eq $v) { "" } else { $v }
            $arr[($nRows - 1), $c] = $val
        }
    }
    $rng = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item($nRows, $nCols))
    $rng.Font.Name = "Calibri"; $rng.Font.Size = 11
    $rng.Value2 = $arr

    if ($TitleLines.Count -ge 1) {
        $titleRng = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, $nCols))
        $titleRng.Merge() | Out-Null
        $titleRng.Font.Bold = $true; $titleRng.Font.Size = 14; $titleRng.Font.Color = Convert-HexToOle "#FFFFFF"
        $titleRng.Interior.Color = Convert-HexToOle $TitleColorHex
    }
    if ($TitleLines.Count -ge 2) {
        $subRng = $ws.Range($ws.Cells.Item(2, 1), $ws.Cells.Item(2, $nCols))
        $subRng.Merge() | Out-Null
    }
    $headerRng = $ws.Range($ws.Cells.Item($headerRowIdx, 1), $ws.Cells.Item($headerRowIdx, $nCols))
    $headerRng.Font.Bold = $true
    $headerRng.Font.Color = Convert-HexToOle "#FFFFFF"
    $headerRng.Interior.Color = Convert-HexToOle $HeaderColorHex
    if ($Rows.Count -gt 0) {
        Set-CurrencyFormat -Ws $ws -ColIndexes $CurrencyColIndexes -FirstRow ($headerRowIdx + 1) -LastRow ($headerRowIdx + $Rows.Count)
        foreach ($dc in $DateColIndexes) { $ws.Range($ws.Cells.Item(($headerRowIdx + 1), $dc), $ws.Cells.Item(($headerRowIdx + $Rows.Count), $dc)).NumberFormatLocal = $Script:FormatoData }
    }
    if ($TotalRow) {
        $totalRng = $ws.Range($ws.Cells.Item($nRows, 1), $ws.Cells.Item($nRows, $nCols))
        $totalRng.Font.Bold = $true
        $totalRng.Font.Color = Convert-HexToOle "#143D2B"
        $totalRng.Interior.Color = Convert-HexToOle $TotalColorHex
        Set-CurrencyFormat -Ws $ws -ColIndexes $CurrencyColIndexes -FirstRow $nRows -LastRow $nRows
        foreach ($dc in $DateColIndexes) { $ws.Cells.Item($nRows, $dc).NumberFormatLocal = $Script:FormatoData }
    }
    try { $ws.Columns.AutoFit() | Out-Null } catch {}
    return $ws
}

function Build-CapaSheet {
    # Aba "Capa": resumo executivo por dia + total geral, no layout escuro do modelo de
    # referencia (Arial, cabecalhos pretos/cinza com texto branco, linhas de dados em cinza claro).
    param($Workbook, $Resumo, $SistemaRecords, [string[]]$Unidades, [datetime[]]$Datas, [string]$Periodo)

    $formasEletronicas = @("CRÉDITO", "DÉBITO", "PIX", "VOUCHER")
    # Demais formas do sistema (dinheiro, conta assinada, conta funcionario...) entram na capa
    # com o nome original do sistema - elas nao tem contrapartida em extrato bancario.
    # Dinheiro vem primeiro entre elas por ser a mais relevante; o resto em ordem alfabetica.
    $formasOutras = @($SistemaRecords |
        Where-Object { $formasEletronicas -notcontains $_.FormaCanonica } |
        Select-Object -ExpandProperty FormaOriginal -Unique |
        Sort-Object @{ Expression = { if ($_ -eq "DINHEIRO") { 0 } else { 1 } } }, @{ Expression = { $_ } })
    $formasTodas = @($formasEletronicas) + @($formasOutras)

    # Numero de colunas se adapta a quantidade de unidades com dados enviados (1, 2 ou mais):
    # uma coluna por unidade + Total A vista/prazo sistema + Total a Vista sistema +
    # Total a vista banco + Diferença.
    $numCols = $Unidades.Count + 4

    $ws = $Workbook.Worksheets.Add()
    $ws.Name = "Capa"
    $ws.Activate()

    $branco = Convert-HexToOle "#FFFFFF"
    $corTitulo = Convert-HexToOle "#142A20"
    $corSubtitulo = Convert-HexToOle "#5B6D62"
    $corDiaFill = Convert-HexToOle "#143D2B"
    $corHeaderFill = Convert-HexToOle "#143D2B"
    $corDataFill = Convert-HexToOle "#EEF5F0"
    $corRodape = Convert-HexToOle "#5B6D62"

    $ws.Cells.Font.Name = "Arial"

    function Get-ValoresForma {
        # Eletronicas: usam o valor ja reclassificado da conciliacao (aba Resumo) e o extrato
        # do banco. Demais formas: total do sistema puro, sem contrapartida bancaria.
        param($Un, $Dt, $Forma)
        if ($formasEletronicas -contains $Forma) {
            if ($Dt) { $rows = @($Resumo | Where-Object { $_.Unidade -eq $Un -and $_.Forma -eq $Forma -and $_.Data -eq $Dt }) }
            else { $rows = @($Resumo | Where-Object { $_.Unidade -eq $Un -and $_.Forma -eq $Forma }) }
            $sistema = ($rows | Measure-Object -Property SistemaAjustado -Sum).Sum
            $banco = ($rows | Measure-Object -Property BancosTotal -Sum).Sum
        } else {
            if ($Dt) { $rows = @($SistemaRecords | Where-Object { $_.Unidade -eq $Un -and $_.FormaOriginal -eq $Forma -and $_.Data -eq $Dt }) }
            else { $rows = @($SistemaRecords | Where-Object { $_.Unidade -eq $Un -and $_.FormaOriginal -eq $Forma }) }
            $sistema = ($rows | Measure-Object -Property Valor -Sum).Sum
            $banco = 0.0
        }
        if ($null -eq $sistema) { $sistema = 0.0 }
        if ($null -eq $banco) { $banco = 0.0 }
        return @{ Sistema = [Math]::Round($sistema, 2); Banco = [Math]::Round($banco, 2) }
    }

    $row = 1
    $ws.Cells.Item($row, 1) = "Conciliação por Forma de Pagamento"
    $tRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $tRng.Merge() | Out-Null
    $tRng.Font.Size = 20; $tRng.Font.Bold = $true; $tRng.Font.Color = $corTitulo
    $tRng.HorizontalAlignment = -4108
    $ws.Rows.Item($row).RowHeight = 30
    $row++

    $ws.Cells.Item($row, 1) = "$($Unidades -join ' e ') | $Periodo"
    $sRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $sRng.Merge() | Out-Null
    $sRng.Font.Size = 12; $sRng.Font.Color = $corSubtitulo
    $sRng.HorizontalAlignment = -4108
    $row += 2

    function Write-BlocoCapa {
        # Recebe a linha inicial e devolve a proxima linha livre (nested function nao
        # compartilha variavel local com a funcao pai, entao passamos/retornamos por valor).
        param([string]$Titulo, $DataFiltro, [int]$Row)

        $ws.Cells.Item($Row, 1) = $Titulo
        $dRng = $ws.Range($ws.Cells.Item($Row, 1), $ws.Cells.Item($Row, $numCols))
        $dRng.Merge() | Out-Null
        $dRng.Font.Size = 13; $dRng.Font.Bold = $true; $dRng.Font.Color = $branco
        $dRng.Interior.Color = $corDiaFill
        $dRng.Borders.Item(9).LineStyle = 1; $dRng.Borders.Item(9).Weight = 2
        $Row++

        $hdrs = @($Unidades) + @("Total A vista/prazo sistema", "Total a Vista sistema", "Total a vista banco", "Diferença")
        for ($c = 0; $c -lt $numCols; $c++) { $ws.Cells.Item($Row, $c + 1) = $hdrs[$c] }
        $hRng = $ws.Range($ws.Cells.Item($Row, 1), $ws.Cells.Item($Row, $numCols))
        $hRng.Font.Bold = $true; $hRng.Font.Color = $branco; $hRng.Interior.Color = $corHeaderFill
        $hRng.HorizontalAlignment = -4108
        # Quebra de linha: "Total A vista/prazo sistema" etc. nao cabem em 1 linha na largura
        # das colunas (ficavam cortados).
        $hRng.WrapText = $true; $hRng.VerticalAlignment = -4108
        $hRng.Rows.Item(1).RowHeight = 32
        $hRng.Borders.Item(9).LineStyle = 1; $hRng.Borders.Item(9).Weight = 2
        $Row++

        # Um total de sistema por unidade (na mesma ordem de $Unidades), mais os totais gerais.
        $sistPorUnidade = @(0.0) * $Unidades.Count
        $bancoAll = 0.0; $recebiveis = 0.0
        $formaTotals = @{}
        foreach ($forma in $formasTodas) {
            $porUnidade = @()
            $bancoForma = 0.0
            for ($i = 0; $i -lt $Unidades.Count; $i++) {
                $v = Get-ValoresForma -Un $Unidades[$i] -Dt $DataFiltro -Forma $forma
                $porUnidade += $v.Sistema
                $sistPorUnidade[$i] += $v.Sistema
                $bancoForma += $v.Banco
            }
            $formaTotals[$forma] = @{ PorUnidade = $porUnidade; Banco = $bancoForma }
            $bancoAll += $bancoForma
            if ($formasEletronicas -contains $forma) { $recebiveis += ($porUnidade | Measure-Object -Sum).Sum }
        }
        $totalGeral = ($sistPorUnidade | Measure-Object -Sum).Sum
        $diferencaTotal = [Math]::Round($bancoAll - $recebiveis, 2)
        $valores = @($sistPorUnidade) + @($totalGeral, $recebiveis, $bancoAll, $diferencaTotal)
        for ($c = 0; $c -lt $numCols; $c++) { $ws.Cells.Item($Row, $c + 1) = $valores[$c] }
        $vRng = $ws.Range($ws.Cells.Item($Row, 1), $ws.Cells.Item($Row, $numCols))
        $vRng.Font.Bold = $true; $vRng.Font.Size = 13; $vRng.HorizontalAlignment = -4108
        $vRng.NumberFormat = $Script:FormatoMoedaSimples
        $vRng.Borders.Item(9).LineStyle = 1; $vRng.Borders.Item(9).Weight = 2
        $Row += 2

        # Vila Moura so concilia Voucher (Remove-RegistrosForaDaRegraUnidade ja descarta as
        # demais formas dela antes da conciliacao) - nessa tabela por forma, uma coluna inteira
        # pra Vila Moura ficaria quase toda zerada. Quando as duas unidades sao exatamente
        # Mooca+Vila Moura, a tabela principal mostra so a Mooca e o valor de Vila Moura sai
        # numa tabela lateral separada, a parte, com a mesma ordem de formas.
        $temVilaMouraLateral = ($Unidades.Count -eq 2 -and $Unidades -contains "VILA MOURA")
        if ($temVilaMouraLateral) {
            $idxVM = [array]::IndexOf($Unidades, "VILA MOURA")
            $idxPrincipal = 1 - $idxVM
            $unidadePrincipal = $Unidades[$idxPrincipal]
            $numColsForma = 5
            $colHeaderVM = $numColsForma + 3
            $colValorVM = $colHeaderVM + 1
        } else {
            $numColsForma = $numCols
        }

        $fh = if ($temVilaMouraLateral) { @("Forma de pagamento", $unidadePrincipal, "Total sistema", "Total extrato banco", "Diferença") }
              else { @("Forma de pagamento") + @($Unidades) + @("Total sistema", "Total extrato banco", "Diferença") }
        for ($c = 0; $c -lt $numColsForma; $c++) { $ws.Cells.Item($Row, $c + 1) = $fh[$c] }
        $fhRng = $ws.Range($ws.Cells.Item($Row, 1), $ws.Cells.Item($Row, $numColsForma))
        $fhRng.Font.Bold = $true; $fhRng.Font.Color = $branco; $fhRng.Interior.Color = $corHeaderFill
        $fhRng.HorizontalAlignment = -4108
        $fhRng.Borders.Item(9).LineStyle = 1; $fhRng.Borders.Item(9).Weight = 2
        if ($temVilaMouraLateral) {
            $vmHdrRng = $ws.Range($ws.Cells.Item($Row, $colHeaderVM), $ws.Cells.Item($Row, $colValorVM))
            $vmHdrRng.Merge() | Out-Null
            $ws.Cells.Item($Row, $colHeaderVM) = "Voucher Vila Moura"
            $vmHdrRng.Font.Bold = $true; $vmHdrRng.Font.Color = $branco; $vmHdrRng.Interior.Color = $corHeaderFill
            $vmHdrRng.HorizontalAlignment = -4108
            $vmHdrRng.Borders.Item(9).LineStyle = 1; $vmHdrRng.Borders.Item(9).Weight = 2
        }
        $Row++

        foreach ($forma in $formasTodas) {
            $ft = $formaTotals[$forma]
            $totalForma = ($ft.PorUnidade | Measure-Object -Sum).Sum
            # Diferenca so faz sentido pras formas eletronicas (unicas com contrapartida no
            # extrato bancario) - nas demais (dinheiro, conta assinada...) fica em branco em
            # vez de mostrar um "banco - sistema" negativo que nao representa divergencia real.
            $diferencaForma = if ($formasEletronicas -contains $forma) { [Math]::Round($ft.Banco - $totalForma, 2) } else { "" }
            $vals = if ($temVilaMouraLateral) { @($forma, $ft.PorUnidade[$idxPrincipal], $totalForma, $ft.Banco, $diferencaForma) }
                    else { @($forma) + @($ft.PorUnidade) + @($totalForma, $ft.Banco, $diferencaForma) }
            for ($c = 0; $c -lt $numColsForma; $c++) { $ws.Cells.Item($Row, $c + 1) = $vals[$c] }
            $frRng = $ws.Range($ws.Cells.Item($Row, 1), $ws.Cells.Item($Row, $numColsForma))
            $frRng.Font.Bold = $true; $frRng.Interior.Color = $corDataFill; $frRng.HorizontalAlignment = -4131
            $ws.Range($ws.Cells.Item($Row, 2), $ws.Cells.Item($Row, $numColsForma)).NumberFormat = $Script:FormatoMoedaSimples
            $frRng.Borders.Item(9).LineStyle = 1; $frRng.Borders.Item(9).Weight = 2
            if ($temVilaMouraLateral) {
                # Rotulo da forma repetido na tabela lateral (coluna do cabecalho "Voucher Vila
                # Moura"), pra ela ser legivel sozinha mesmo quando a tabela principal (coluna A)
                # esta rolada pra fora da tela.
                $ws.Cells.Item($Row, $colHeaderVM) = $forma
                $ws.Cells.Item($Row, $colValorVM) = $ft.PorUnidade[$idxVM]
                $vmRowRng = $ws.Range($ws.Cells.Item($Row, $colHeaderVM), $ws.Cells.Item($Row, $colValorVM))
                $vmRowRng.Font.Bold = $true; $vmRowRng.Interior.Color = $corDataFill; $vmRowRng.HorizontalAlignment = -4131
                $ws.Cells.Item($Row, $colValorVM).NumberFormat = $Script:FormatoMoedaSimples
                $vmRowRng.Borders.Item(9).LineStyle = 1; $vmRowRng.Borders.Item(9).Weight = 2
            }
            $Row++
        }

        $totVals = if ($temVilaMouraLateral) { @("TOTAL", $sistPorUnidade[$idxPrincipal], $totalGeral, $bancoAll, $diferencaTotal) }
                   else { @("TOTAL") + @($sistPorUnidade) + @($totalGeral, $bancoAll, $diferencaTotal) }
        for ($c = 0; $c -lt $numColsForma; $c++) { $ws.Cells.Item($Row, $c + 1) = $totVals[$c] }
        $trRng = $ws.Range($ws.Cells.Item($Row, 1), $ws.Cells.Item($Row, $numColsForma))
        $trRng.Font.Bold = $true; $trRng.Font.Color = $branco; $trRng.Interior.Color = $corHeaderFill; $trRng.HorizontalAlignment = -4131
        $ws.Range($ws.Cells.Item($Row, 2), $ws.Cells.Item($Row, $numColsForma)).NumberFormat = $Script:FormatoMoedaSimples
        $trRng.Borders.Item(9).LineStyle = 1; $trRng.Borders.Item(9).Weight = 2
        if ($temVilaMouraLateral) {
            $ws.Cells.Item($Row, $colHeaderVM) = "TOTAL"
            $ws.Cells.Item($Row, $colValorVM) = $sistPorUnidade[$idxVM]
            $vmTotRng = $ws.Range($ws.Cells.Item($Row, $colHeaderVM), $ws.Cells.Item($Row, $colValorVM))
            $vmTotRng.Font.Bold = $true; $vmTotRng.Font.Color = $branco; $vmTotRng.Interior.Color = $corHeaderFill; $vmTotRng.HorizontalAlignment = -4131
            $ws.Cells.Item($Row, $colValorVM).NumberFormat = $Script:FormatoMoedaSimples
            $vmTotRng.Borders.Item(9).LineStyle = 1; $vmTotRng.Borders.Item(9).Weight = 2
        }
        $Row += 2
        return $Row
    }

    foreach ($dt in $Datas) { $row = Write-BlocoCapa -Titulo "Dia $($dt.ToString('dd/MM/yyyy'))" -DataFiltro $dt -Row $row }
    # Com um unico dia, o bloco "Total Geral" seria identico ao bloco do dia - nao duplica.
    if ($Datas.Count -gt 1) {
        $row = Write-BlocoCapa -Titulo "Total Geral ($Periodo)" -DataFiltro $null -Row $row
    }

    $ws.Cells.Item($row, 1) = "Fechamento do sistema por forma de pagamento. Crédito, Débito, PIX e Voucher já aparecem reclassificados pela conciliação (aba Resumo) e compõem o Total a Vista sistema; as demais formas são o total do sistema. Total extrato banco cobre apenas as formas eletrônicas (C6 + Sicredi). Diferença = Total extrato banco - Total sistema, só calculada para as formas eletrônicas. Consulte as demais abas para detalhamento (trocas de forma aparecem destacadas na aba Diferencas_Detalhadas)."
    $foRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $foRng.Merge() | Out-Null
    $foRng.Font.Size = 9; $foRng.Font.Italic = $true; $foRng.Font.Color = $corRodape

    $ws.Columns.Item(1).ColumnWidth = 29.36
    for ($c = 2; $c -le $numCols; $c++) { $ws.Columns.Item($c).ColumnWidth = 17.36 }
    # Larguras da tabela lateral de Vila Moura (ver Write-BlocoCapa): so a coluna G e o
    # respiro estreito - a coluna F NAO pode ser estreitada, porque o bloco-resumo do topo de
    # cada dia usa 6 colunas (A-F, a ultima e "Diferenca") e ela aparecia como "###". Coluna H =
    # rotulo (forma), com a mesma largura da coluna A; coluna I = valor, largura das demais.
    if ($Unidades.Count -eq 2 -and $Unidades -contains "VILA MOURA") {
        $ws.Columns.Item(7).ColumnWidth = 4
        $ws.Columns.Item(8).ColumnWidth = 29.36
        $ws.Columns.Item(9).ColumnWidth = 17.36
    }
    try { $ws.Application.ActiveWindow.DisplayGridlines = $false } catch {}
    return $ws
}

function Export-RelatorioExcel {
    param($ExcelApp, $Resultado, $Resumo, $ResumoDiario, $SistemaRecords, $BancoRecords, [string]$OutputPath)

    $ExcelApp.DisplayAlerts = $false
    $wb = $ExcelApp.Workbooks.Add()
    while ($wb.Worksheets.Count -gt 1) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }
    $sheetOriginal = $wb.Worksheets.Item(1)

    $periodo = ""
    $datasOrdenadas = @($SistemaRecords | Select-Object -ExpandProperty Data -Unique | Sort-Object)
    if ($datasOrdenadas.Count -gt 0) {
        $periodo = "$($datasOrdenadas[0].ToString('dd/MM/yyyy')) A $($datasOrdenadas[-1].ToString('dd/MM/yyyy'))"
    }
    $unidadesOrdenadas = @($SistemaRecords | Select-Object -ExpandProperty Unidade -Unique | Sort-Object)

    # --- Capa ---
    Build-CapaSheet -Workbook $wb -Resumo $Resumo -SistemaRecords $SistemaRecords -Unidades $unidadesOrdenadas -Datas $datasOrdenadas -Periodo $periodo | Out-Null

    # --- Resumo (por Unidade/Data/Forma) ---
    $rowsResumo = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Resumo) {
        $rowsResumo.Add(@(
            $r.Unidade, $r.Data, $r.Forma,
            $r.SistemaOriginal, $r.Reclassificacao, $r.AjusteCentavos, $r.SistemaAjustado,
            $r.C6Bruto, $r.SicrediBruto, $r.BancosTotal,
            $r.SaldoOriginal, $r.SaldoAjustado, $r.Status, $r.IdSaldo
        )) | Out-Null
    }
    $totSistemaOrig = [Math]::Round((($Resumo | Measure-Object -Property SistemaOriginal -Sum).Sum), 2)
    $totReclass = [Math]::Round((($Resumo | Measure-Object -Property Reclassificacao -Sum).Sum), 2)
    $totCentavos = [Math]::Round((($Resumo | Measure-Object -Property AjusteCentavos -Sum).Sum), 2)
    $totSistemaAjust = [Math]::Round((($Resumo | Measure-Object -Property SistemaAjustado -Sum).Sum), 2)
    $totC6 = [Math]::Round((($Resumo | Measure-Object -Property C6Bruto -Sum).Sum), 2)
    $totSicredi = [Math]::Round((($Resumo | Measure-Object -Property SicrediBruto -Sum).Sum), 2)
    $totBancos = [Math]::Round((($Resumo | Measure-Object -Property BancosTotal -Sum).Sum), 2)
    $totSaldoOrig = [Math]::Round((($Resumo | Measure-Object -Property SaldoOriginal -Sum).Sum), 2)
    $totSaldoAjust = [Math]::Round((($Resumo | Measure-Object -Property SaldoAjustado -Sum).Sum), 2)
    $statusGeral = "OK"; if ([Math]::Abs($totSaldoAjust) -ge 0.01) { $statusGeral = "DIVERGÊNCIA" }
    $totalRowResumo = @("TOTAL GERAL", "", "", $totSistemaOrig, $totReclass, $totCentavos, $totSistemaAjust, $totC6, $totSicredi, $totBancos, $totSaldoOrig, $totSaldoAjust, $statusGeral, "")

    Write-TitledSheet -Workbook $wb -SheetName "Resumo" `
        -TitleLines @(
            "CONCILIAÇÃO ELETRÔNICA — $periodo",
            "Escopo: Crédito, Débito, PIX e Voucher. Bancos considerados: C6 + Sicredi. Recusadas/não autorizadas/devolvidas/desfeitas foram excluídas. Trocas de forma e vendas divididas foram reclassificadas antes do saldo final."
        ) `
        -Headers @("Unidade","Data","Forma","Sistema original","Reclassificação","Ajuste centavos","Sistema ajustado","C6 bruto","Sicredi bruto","Bancos total","Saldo original","Saldo ajustado","Status","ID Saldo") `
        -Rows $rowsResumo -TotalRow $totalRowResumo -DateColIndexes @(2) -CurrencyColIndexes @(4,5,6,7,8,9,10,11,12) `
        -TitleColorHex "#143D2B" -HeaderColorHex "#143D2B" -TotalColorHex "#E3F2E8" | Out-Null

    # --- Resumo_Diario (por Unidade/Data) ---
    $rowsDiario = New-Object System.Collections.Generic.List[object]
    foreach ($r in $ResumoDiario) {
        $rowsDiario.Add(@($r.Unidade, $r.Data, $r.SistemaOriginal, $r.SistemaAjustado, $r.C6Bruto, $r.SicrediBruto, $r.BancosTotal, $r.SaldoOriginal, $r.SaldoAjustado, $r.Status)) | Out-Null
    }
    $dTotSistemaOrig = [Math]::Round((($ResumoDiario | Measure-Object -Property SistemaOriginal -Sum).Sum), 2)
    $dTotSistemaAjust = [Math]::Round((($ResumoDiario | Measure-Object -Property SistemaAjustado -Sum).Sum), 2)
    $dTotC6 = [Math]::Round((($ResumoDiario | Measure-Object -Property C6Bruto -Sum).Sum), 2)
    $dTotSicredi = [Math]::Round((($ResumoDiario | Measure-Object -Property SicrediBruto -Sum).Sum), 2)
    $dTotBancos = [Math]::Round((($ResumoDiario | Measure-Object -Property BancosTotal -Sum).Sum), 2)
    $dTotSaldoOrig = [Math]::Round((($ResumoDiario | Measure-Object -Property SaldoOriginal -Sum).Sum), 2)
    $dTotSaldoAjust = [Math]::Round((($ResumoDiario | Measure-Object -Property SaldoAjustado -Sum).Sum), 2)
    $dStatusGeral = "OK"; if ([Math]::Abs($dTotSaldoAjust) -ge 0.01) { $dStatusGeral = "DIVERGÊNCIA" }
    $totalRowDiario = @("TOTAL GERAL", "", $dTotSistemaOrig, $dTotSistemaAjust, $dTotC6, $dTotSicredi, $dTotBancos, $dTotSaldoOrig, $dTotSaldoAjust, $dStatusGeral)

    Write-TitledSheet -Workbook $wb -SheetName "Resumo_Diario" `
        -TitleLines @("RESUMO POR UNIDADE E DIA", "Saldo negativo = banco maior que o sistema; saldo positivo = sistema maior que o banco.") `
        -Headers @("Unidade","Data","Sistema original","Sistema ajustado","C6","Sicredi","Bancos total","Saldo original","Saldo ajustado","Status") `
        -Rows $rowsDiario -TotalRow $totalRowDiario -DateColIndexes @(2) -CurrencyColIndexes @(3,4,5,6,7,8,9) `
        -TitleColorHex "#143D2B" -HeaderColorHex "#143D2B" -TotalColorHex "#E3F2E8" | Out-Null

    # --- Diferencas_Detalhadas ---
    $rowsDetalhe = Build-DiferencasDetalhadas -Resumo $Resumo -Grupos $Resultado.Grupos -SobrasSistema $Resultado.SobrasSistema -SobrasBanco $Resultado.SobrasBanco
    $wsDetalhe = Write-SheetFromRows -Workbook $wb -SheetName "Diferencas_Detalhadas" -Headers @(
        "ID Saldo","Unidade","Data","Forma","Tipo diferença","Hora sistema","Valor sistema","ID venda sistema",
        "Banco","Hora banco","Valor banco","Autorização","NSU/Comprovante","Terminal/Série","Impacto no saldo","Saldo do grupo","Observação"
    ) -Rows $rowsDetalhe -DateColIndexes @(3) -CurrencyColIndexes @(7,11,15,16)

    # Destaca as linhas de troca de forma (ex.: DEBITO reclassificado como CREDITO) pra ficarem
    # visiveis a olho junto das demais diferencas, em vez de somente na aba Ajustes_Reclassif.
    $corTroca = Convert-HexToOle "#FBF0DC"
    for ($r = 0; $r -lt $rowsDetalhe.Count; $r++) {
        if ($rowsDetalhe[$r][4] -eq "TROCA DE FORMA") {
            $wsDetalhe.Range($wsDetalhe.Cells.Item($r + 2, 1), $wsDetalhe.Cells.Item($r + 2, 17)).Interior.Color = $corTroca
        }
    }

    # --- Ajustes_Reclassif ---
    $rowsAjustes = Build-AjustesReclassif -Grupos $Resultado.Grupos
    Write-SheetFromRows -Workbook $wb -SheetName "Ajustes_Reclassif" -Headers @(
        "Unidade","Data","Forma impactada","Tipo ajuste","Impacto","Descrição","ID venda sistema","RID sistema","RID banco","Hora sistema","Hora banco","Banco"
    ) -Rows $rowsAjustes -DateColIndexes @(2) -CurrencyColIndexes @(5) | Out-Null

    # --- Base_Sistema (dump bruto, rastreabilidade total) ---
    $rowsBaseSis = New-Object System.Collections.Generic.List[object]
    foreach ($r in ($SistemaRecords | Sort-Object Unidade, Data, DataHora)) {
        $rowsBaseSis.Add(@($r.RID, $r.Unidade, $r.Data, (Format-HoraBR $r.Hora), $r.FormaOriginal, $r.FormaCanonica, [Math]::Round($r.Valor,2), $r.IdVenda, $r.IdAbertura)) | Out-Null
    }
    Write-SheetFromRows -Workbook $wb -SheetName "Base_Sistema" -Headers @("RID","Unidade","Data","Hora","Forma original","Forma normalizada","Valor sistema","ID venda","ID abertura") -Rows $rowsBaseSis -DateColIndexes @(3) -CurrencyColIndexes @(7) | Out-Null

    # --- Base_Bancos (dump bruto, rastreabilidade total) ---
    $rowsBaseBk = New-Object System.Collections.Generic.List[object]
    foreach ($r in ($BancoRecords | Sort-Object Banco, Unidade, Data, DataHora)) {
        $rowsBaseBk.Add(@(
            $r.RID, $r.Banco, $r.Unidade, $r.Data, (Format-HoraBR $r.Hora), $r.FormaCanonica, [Math]::Round($r.Valor,2), $r.Status,
            $r.TerminalDisplay, $r.CodigoAutorizacao, $r.NsuComprovante, $r.CodigoVendaPedido, $r.Referencia
        )) | Out-Null
    }
    Write-SheetFromRows -Workbook $wb -SheetName "Base_Bancos" -Headers @("RID","Banco","Unidade","Data","Hora","Forma","Valor bruto","Status","Terminal/Série","Autorização","NSU/Comprovante","Código venda/pedido","Referência") -Rows $rowsBaseBk -DateColIndexes @(4) -CurrencyColIndexes @(7) | Out-Null

    $sheetOriginal.Delete()

    $wb.Worksheets.Item("Capa").Activate()
    $wb.Worksheets.Item("Capa").Range("A1").Select() | Out-Null

    $wb.SaveAs($OutputPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
    $wb.Close($false)
    return $OutputPath
}

# ============================================================================
# FECHAMENTO CP E DRE
# ============================================================================
# Modulo de fechamento de Contas a Pagar + DRE Gerencial, baseado no modelo de planilha
# enviado pelo usuario ("Fechamento CP e DRE Vencimentos Agosto 2026 - Panetteria 77.xlsx").
# Dois modos possiveis (escolhidos na tela):
#   - Vencimento:  despesa = titulos pela D.Vencimento; receita = extrato dos bancos relacionados.
#   - Competencia: despesa = lancamentos pela D.Lancamento; receita = faturamento do sistema no periodo.
# A planilha de despesa tem sempre a mesma estrutura de 37 colunas (export do financeiro),
# independente do modo. A planilha de receita ainda nao tem modelo definitivo - Read-ReceitaFile
# eh um leitor PROVISORIO (Unidade/Data/Valor) que sera trocado quando o modelo chegar; nada
# mais no pipeline depende do formato exato dessa planilha.

$Script:MapaMacroDREPadrao = @{
    "CUSTO DE MERCADORIA VENDIDA" = "CMV"; "CMV PADARIA" = "CMV"; "CMV CONFEITARIA" = "CMV"
    "CMV SALGATERIA" = "CMV"; "CMV EMPORIUM" = "CMV"; "CMV REFRIGERANTES" = "CMV"
    "CMV VINHOS E DESTILADOS" = "CMV"; "CMV RESTAURANTE" = "CMV"; "CMV COZINHA PRODUCAO" = "CMV"
    "CMV ROTISSERIA" = "CMV"; "ACORDOS" = "CMV"; "CMV EMBALAGENS" = "CMV"
    "ICMS" = "CMV"; "ISS" = "CMV"; "PIS" = "CMV"; "COFINS" = "CMV"; "DARE" = "CMV"
    "GUIA UNIFICADA" = "CMV"; "IRPJ" = "CMV"; "CSLL" = "CMV"
    "FOLHA DE PAGAMENTO CLT" = "DESPESAS FUNCIONARIOS"; "FOLHA DE PAGAMENTO PJ" = "DESPESAS FUNCIONARIOS"
    "ADIANTAMENTO CLT" = "DESPESAS FUNCIONARIOS"; "ADIANTAMENTO PJ" = "DESPESAS FUNCIONARIOS"
    "SIMPLES NACIONAL" = "DESPESAS FUNCIONARIOS"; "INSS" = "DESPESAS FUNCIONARIOS"; "FGTS" = "DESPESAS FUNCIONARIOS"
    "IR" = "DESPESAS FUNCIONARIOS"; "ENCARGOS SOBRE RESCISAO" = "DESPESAS FUNCIONARIOS"
    "VALE TRANSPORTE" = "DESPESAS FUNCIONARIOS"; "VALE REFEICAO/ALIMENTACAO" = "DESPESAS FUNCIONARIOS"
    "CONVENIOS MEDICOS E ODONTO" = "DESPESAS FUNCIONARIOS"; "OUTROS BENEFICIOS" = "DESPESAS FUNCIONARIOS"
    "CONSUMO INTERNO FUNCIONARIOS" = "DESPESAS FUNCIONARIOS"; "FERIAS" = "DESPESAS FUNCIONARIOS"
    "DECIMO TERCEIRO" = "DESPESAS FUNCIONARIOS"; "CURSOS E CAPACITACOES" = "DESPESAS FUNCIONARIOS"
    "EVENTOS INTERNOS" = "DESPESAS FUNCIONARIOS"; "VERBAS RESCISORIAS" = "DESPESAS FUNCIONARIOS"
    "MULTA RESCISORIA" = "DESPESAS FUNCIONARIOS"; "CUSTOS JURIDICOS" = "DESPESAS FUNCIONARIOS"
    "EXAMES ADMISSIONAIS" = "DESPESAS FUNCIONARIOS"; "EXAMES DEMISSIONAIS" = "DESPESAS FUNCIONARIOS"
    "OUTROS EXAMES OCUPACIONAIS" = "DESPESAS FUNCIONARIOS"; "COMISSOES DE VENDAS" = "DESPESAS FUNCIONARIOS"
    "DOBRAS" = "DESPESAS FUNCIONARIOS"
    "ENERGIA ELETRICA" = "DESPESAS OPERACIONAIS"; "AGUA E ESGOTO" = "DESPESAS OPERACIONAIS"; "GAS" = "DESPESAS OPERACIONAIS"
    "TAXAS MUNICIPAIS" = "DESPESAS ADMINISTRATIVAS"; "TAXAS ESTADUAIS" = "DESPESAS ADMINISTRATIVAS"
    "TAXAS FEDERAIS" = "DESPESAS ADMINISTRATIVAS"; "MATERIAIS DE ESCRITORIO" = "DESPESAS ADMINISTRATIVAS"
    "DESPESAS DIVERSAS ADMINISTRATIVAS" = "DESPESAS ADMINISTRATIVAS"; "DESPESAS CARTORARIAS" = "DESPESAS ADMINISTRATIVAS"
    "MATERIAIS DE LIMPEZA" = "DESPESAS ADMINISTRATIVAS"; "SEGURO" = "DESPESAS ADMINISTRATIVAS"
    "ALUGUEL" = "DESPESAS OCUPACAO"; "CONDOMINIO / IPTU" = "DESPESAS OCUPACAO"
    "PROMOCOES SAZONAIS" = "DESPESAS COM VENDAS"; "PROMOCOES RECORRENTES" = "DESPESAS COM VENDAS"
    "FRETES" = "DESPESAS COM VENDAS"; "COMBUSTIVEL" = "DESPESAS COM VENDAS"; "MANUTENCAO VEICULOS" = "DESPESAS COM VENDAS"
    "LICENCIAMENTO DE SOFTWARES" = "DESPESAS COM TECNOLOGIA / TI"; "SUPORTE TECNICO E MANUTENCAO DE TI" = "DESPESAS COM TECNOLOGIA / TI"
    "DESENVOLVIMENTO DE SOFTWARE" = "DESPESAS COM TECNOLOGIA / TI"; "MANUTENCAO DE INFRAESTRUTURA" = "DESPESAS COM TECNOLOGIA / TI"
    "COMPRA DE HARDWARE" = "DESPESAS COM TECNOLOGIA / TI"; "INTERNET E TELEFONE" = "DESPESAS COM TECNOLOGIA / TI"
    "DESCONTOS" = "DESPESAS POR PERDAS"; "DEVOLUCOES" = "DESPESAS POR PERDAS"; "DOACOES" = "DESPESAS POR PERDAS"
    "DESPERDICIO/PERDAS" = "DESPESAS POR PERDAS"
    "SEGURANCA" = "DESPESAS COM PRESTADORES"; "CONTABILIDADE" = "DESPESAS COM PRESTADORES"; "JURIDICO" = "DESPESAS COM PRESTADORES"
    "DEDETIZACAO\DESENTUPIDORA" = "DESPESAS COM PRESTADORES"; "RECOLHIMENTO DE LIXO" = "DESPESAS COM PRESTADORES"
    "DESPESAS FINANCEIRAS - JUROS" = "DESPESAS FINANCEIRAS"; "DESPESAS FINANCEIRAS - TARIFAS BANCARIAS" = "DESPESAS FINANCEIRAS"
    "DESPESAS FINANCEIRAS - ANTECIPACAO" = "DESPESAS FINANCEIRAS"; "TAXA DE CARTAO" = "DESPESAS FINANCEIRAS"
    "TAXA IFOOD" = "DESPESAS FINANCEIRAS"; "TAXA KEETA" = "DESPESAS FINANCEIRAS"; "TAXA 99" = "DESPESAS FINANCEIRAS"
    "PUBLICIDADE E PROPAGANDA" = "MARKETING"; "PRODUCAO DE CONTEUDO" = "MARKETING"; "INFLUENCIADORES" = "MARKETING"
    "LUCROS MENSAIS" = "DISTRIBUICAO DE LUCROS"; "LUCROS TRIMESTRAIS" = "DISTRIBUICAO DE LUCROS"; "LUCROS ANUAIS" = "DISTRIBUICAO DE LUCROS"
    "EQUIPAMENTOS" = "INVESTIMENTOS"; "MOBILIARIO" = "INVESTIMENTOS"; "OBRAS / REFORMAS" = "INVESTIMENTOS"
    "PARCELAMENTO DA COMPRA DA PADARIA" = "INVESTIMENTOS"; "TRANSFERENCIAS/CUSTOS ESCRIT/JURIDI" = "INVESTIMENTOS"
    "EMPRESTIMOS E FINANCIAMENTOS" = "EMPRESTIMOS E FINANCIAMENTOS"
}

# Ordem das categorias macro na cascata da DRE (igual ao modelo de referencia).
$Script:MacroDREOrdemDRE = @(
    "DESPESAS POR PERDAS", "CMV", "DESPESAS FUNCIONARIOS", "DESPESAS OPERACIONAIS", "DESPESAS ADMINISTRATIVAS",
    "DESPESAS OCUPACAO", "DESPESAS COM VENDAS", "DESPESAS COM TECNOLOGIA / TI", "DESPESAS COM PRESTADORES",
    "DESPESAS FINANCEIRAS", "MARKETING", "DISTRIBUICAO DE LUCROS", "INVESTIMENTOS", "EMPRESTIMOS E FINANCIAMENTOS"
)
# As 9 categorias somadas entre Receita Operacional Liquida e o EBITDA.
$Script:MacroDREOpex = @(
    "DESPESAS FUNCIONARIOS", "DESPESAS OPERACIONAIS", "DESPESAS ADMINISTRATIVAS", "DESPESAS OCUPACAO",
    "DESPESAS COM VENDAS", "DESPESAS COM TECNOLOGIA / TI", "DESPESAS COM PRESTADORES", "DESPESAS FINANCEIRAS", "MARKETING"
)

$Script:FechamentoConfigPath = Join-Path (Get-AppDirectory) "config_fechamento.json"

function Load-FechamentoConfig {
    if (Test-Path $Script:FechamentoConfigPath) {
        try {
            $raw = Get-Content $Script:FechamentoConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $mapa = @{}
            $raw.MapaMacroDRE.PSObject.Properties | ForEach-Object { $mapa[$_.Name] = $_.Value }
            if ($mapa.Count -eq 0) { $mapa = $Script:MapaMacroDREPadrao.Clone() }
            return @{ MapaMacroDRE = $mapa }
        } catch { return @{ MapaMacroDRE = $Script:MapaMacroDREPadrao.Clone() } }
    }
    return @{ MapaMacroDRE = $Script:MapaMacroDREPadrao.Clone() }
}

function Save-FechamentoConfig {
    param($MapaMacroDRE)
    $obj = @{ MapaMacroDRE = $MapaMacroDRE }
    $obj | ConvertTo-Json | Out-File -FilePath $Script:FechamentoConfigPath -Encoding UTF8
}

function Find-HeaderRowEmQualquerAba {
    # Algumas planilhas de origem trazem varias abas (ex.: o modelo original tinha Base
    # Vencimentos/Base Pagamentos numa planilha so) - procura o cabecalho esperado em cada
    # aba do workbook ate achar, em vez de assumir que esta sempre na aba 1.
    param($Workbook, [string[]]$RequiredHeaders)
    foreach ($candidata in $Workbook.Worksheets) {
        try { return Find-HeaderRow -Worksheet $candidata -RequiredHeaders $RequiredHeaders -MaxScanRows 30 | Add-Member -NotePropertyName Worksheet -NotePropertyValue $candidata -PassThru }
        catch {}
    }
    return $null
}

function Read-DespesaFile {
    # Le a planilha de contas a pagar (37 colunas, mesma estrutura tanto para vencimento
    # quanto para competencia). $Modo define qual data vira o campo "Data" de cada registro:
    # "Vencimento" -> D. Vencimento; "Competencia" -> D. Lancamento.
    param($ExcelApp, [string]$Path, [string]$Modo, $MapaMacroDRE, [string]$Password = "")
    $ctx = Open-WorkbookRobust -ExcelApp $ExcelApp -Path $Path -Password $Password
    try {
        $reqHeaders = @("D. Vencimento", "V. Título", "Fantasia Empresa", "Descrição C. Gerencial")
        $hdr = Find-HeaderRowEmQualquerAba -Workbook $ctx.Workbook -RequiredHeaders $reqHeaders
        if (-not $hdr) { throw "Nao encontrei as colunas esperadas de contas a pagar (D. Vencimento, V. Titulo, Fantasia Empresa, Descricao C. Gerencial) em '$Path'." }
        $ws = $hdr.Worksheet

        $lastRow = $ws.UsedRange.Rows.Count
        $rng = $ws.Range($ws.Cells.Item($hdr.Row, 1), $ws.Cells.Item($lastRow, $hdr.MaxCol))
        $arr = $rng.Value2
        $n = $arr.GetLength(0)
        $cVenc = $hdr.Map["d. vencimento"]
        $cLanc = if ($hdr.Map.ContainsKey("d. lançamento")) { $hdr.Map["d. lançamento"] } else { $null }
        $cLiq = if ($hdr.Map.ContainsKey("d. liquidação")) { $hdr.Map["d. liquidação"] } else { $null }
        $cEmpresa = $hdr.Map["fantasia empresa"]; $cDescricao = $hdr.Map["descrição c. gerencial"]
        $cTitulo = $hdr.Map["v. título"]
        $cPosicao = if ($hdr.Map.ContainsKey("posição")) { $hdr.Map["posição"] } else { $null }
        $cAtraso = if ($hdr.Map.ContainsKey("dias atraso")) { $hdr.Map["dias atraso"] } else { $null }

        $records = New-Object System.Collections.Generic.List[object]
        for ($r = 2; $r -le $n; $r++) {
            $dataVenc = ConvertTo-DateSafe $arr[$r, $cVenc]
            $dataLanc = if ($cLanc) { ConvertTo-DateSafe $arr[$r, $cLanc] } else { $null }
            $dataLiq = if ($cLiq) { ConvertTo-DateSafe $arr[$r, $cLiq] } else { $null }
            $data = if ($Modo -eq "Competencia") { $dataLanc } else { $dataVenc }
            if ($null -eq $data) { continue }
            $unidade = "$($arr[$r, $cEmpresa])".Trim()
            if ($unidade -eq "") { continue }
            $descricao = "$($arr[$r, $cDescricao])".Trim()
            $descricaoChave = $descricao.ToUpperInvariant()
            $valor = ConvertTo-DecimalAny $arr[$r, $cTitulo]
            $macro = if ($descricaoChave -ne "" -and $MapaMacroDRE.ContainsKey($descricaoChave)) { $MapaMacroDRE[$descricaoChave] } else { "NÃO MAPEADO" }
            $posicaoVal = if ($cPosicao) { "$($arr[$r, $cPosicao])".Trim() } else { "" }
            $diasAtrasoVal = if ($cAtraso) { ConvertTo-DecimalAny $arr[$r, $cAtraso] } else { 0.0 }
            $records.Add([PSCustomObject]@{
                Unidade = $unidade; Data = $data
                DataVencimento = $dataVenc; DataLancamento = $dataLanc; DataLiquidacao = $dataLiq
                DescricaoGerencial = $descricao; MacroDRE = $macro; Valor = $valor
                Posicao = $posicaoVal; DiasAtraso = $diasAtrasoVal
                ArquivoOrigem = [System.IO.Path]::GetFileName($Path)
            }) | Out-Null
        }
        return $records
    } finally { Close-WorkbookCtx -Ctx $ctx }
}

function Read-ReceitaFile {
    # Leitor PROVISORIO: o modelo definitivo da planilha de receita ainda vai ser enviado.
    # Aceita por enquanto um formato generico de 3 colunas (Unidade, Data, Valor), que serve
    # tanto pra faturamento por competencia quanto pra um extrato bancario ja resumido.
    # Quando o modelo real chegar, so esta funcao precisa mudar - o resto do pipeline nao muda.
    param($ExcelApp, [string]$Path, [string]$Password = "")
    $ctx = Open-WorkbookRobust -ExcelApp $ExcelApp -Path $Path -Password $Password
    try {
        $reqHeaders = @("Unidade", "Data", "Valor")
        $hdr = Find-HeaderRowEmQualquerAba -Workbook $ctx.Workbook -RequiredHeaders $reqHeaders
        if (-not $hdr) { throw "Nao encontrei as colunas esperadas de receita (Unidade, Data, Valor) em '$Path'. O modelo definitivo dessa planilha ainda vai ser definido - ajuste Read-ReceitaFile quando ele chegar." }
        $ws = $hdr.Worksheet

        $lastRow = $ws.UsedRange.Rows.Count
        $rng = $ws.Range($ws.Cells.Item($hdr.Row, 1), $ws.Cells.Item($lastRow, $hdr.MaxCol))
        $arr = $rng.Value2
        $n = $arr.GetLength(0)
        $cUnidade = $hdr.Map["unidade"]; $cData = $hdr.Map["data"]; $cValor = $hdr.Map["valor"]

        $records = New-Object System.Collections.Generic.List[object]
        for ($r = 2; $r -le $n; $r++) {
            $data = ConvertTo-DateSafe $arr[$r, $cData]
            if ($null -eq $data) { continue }
            $unidade = "$($arr[$r, $cUnidade])".Trim()
            if ($unidade -eq "") { continue }
            $valor = ConvertTo-DecimalAny $arr[$r, $cValor]
            $records.Add([PSCustomObject]@{ Unidade = $unidade; Data = $data; Valor = $valor; ArquivoOrigem = [System.IO.Path]::GetFileName($Path) }) | Out-Null
        }
        return $records
    } finally { Close-WorkbookCtx -Ctx $ctx }
}

function Compute-Fechamento {
    # Agrega despesas e receita por unidade (e um pseudo-unidade "CONSOLIDADO" que soma tudo,
    # calculado no mesmo lugar pra nao precisar de um caminho de codigo separado) e monta a
    # cascata da DRE por unidade. Generaliza pra N unidades (nao assume Mooca/Moura fixos),
    # igual a Capa da Conciliacao.
    param($DespesaRecords, $ReceitaRecords)

    $CONS = "CONSOLIDADO"
    $unidades = @(@($DespesaRecords | Select-Object -ExpandProperty Unidade) + @($ReceitaRecords | Select-Object -ExpandProperty Unidade) | Select-Object -Unique | Sort-Object)
    $unidadesComConsolidado = @($unidades) + @($CONS)

    $datasDespesa = @($DespesaRecords | Select-Object -ExpandProperty Data -Unique | Sort-Object)
    $periodo = ""
    if ($datasDespesa.Count -gt 0) { $periodo = "$($datasDespesa[0].ToString('dd/MM/yyyy')) A $($datasDespesa[-1].ToString('dd/MM/yyyy'))" }

    $faturamentoPorUnidade = @{}
    foreach ($u in $unidades) {
        $faturamentoPorUnidade[$u] = [Math]::Round((($ReceitaRecords | Where-Object { $_.Unidade -eq $u } | Measure-Object -Property Valor -Sum).Sum), 2)
    }
    $faturamentoPorUnidade[$CONS] = [Math]::Round((($ReceitaRecords | Measure-Object -Property Valor -Sum).Sum), 2)

    $totalPorMacroUnidade = @{}
    $totalPorCategoriaUnidade = @{}
    foreach ($d in $DespesaRecords) {
        foreach ($uKey in @($d.Unidade, $CONS)) {
            $km = "$uKey|$($d.MacroDRE)"
            if (-not $totalPorMacroUnidade.ContainsKey($km)) { $totalPorMacroUnidade[$km] = 0.0 }
            $totalPorMacroUnidade[$km] += $d.Valor

            $kc = "$uKey|$($d.DescricaoGerencial)"
            if (-not $totalPorCategoriaUnidade.ContainsKey($kc)) { $totalPorCategoriaUnidade[$kc] = @{ Macro = $d.MacroDRE; Valor = 0.0 } }
            $totalPorCategoriaUnidade[$kc].Valor += $d.Valor
        }
    }

    function Get-DREUnidade {
        param([string]$U)
        $bruto = 0.0; if ($faturamentoPorUnidade.ContainsKey($U)) { $bruto = $faturamentoPorUnidade[$U] }
        $perdas = 0.0; $k = "$U|DESPESAS POR PERDAS"; if ($totalPorMacroUnidade.ContainsKey($k)) { $perdas = $totalPorMacroUnidade[$k] }
        $liquido = $bruto - $perdas
        $cmv = 0.0; $k = "$U|CMV"; if ($totalPorMacroUnidade.ContainsKey($k)) { $cmv = $totalPorMacroUnidade[$k] }
        $rol = $liquido - $cmv
        $opex = @{}; $totalOpex = 0.0
        foreach ($m in $Script:MacroDREOpex) {
            $v = 0.0; $k = "$U|$m"; if ($totalPorMacroUnidade.ContainsKey($k)) { $v = $totalPorMacroUnidade[$k] }
            $opex[$m] = [Math]::Round($v, 2); $totalOpex += $v
        }
        $ebitda = $rol - $totalOpex
        $distrib = 0.0; $k = "$U|DISTRIBUICAO DE LUCROS"; if ($totalPorMacroUnidade.ContainsKey($k)) { $distrib = $totalPorMacroUnidade[$k] }
        $invest = 0.0; $k = "$U|INVESTIMENTOS"; if ($totalPorMacroUnidade.ContainsKey($k)) { $invest = $totalPorMacroUnidade[$k] }
        $emprest = 0.0; $k = "$U|EMPRESTIMOS E FINANCIAMENTOS"; if ($totalPorMacroUnidade.ContainsKey($k)) { $emprest = $totalPorMacroUnidade[$k] }
        $resultado = $ebitda - $distrib - $invest - $emprest
        return [PSCustomObject]@{
            Unidade = $U; FaturamentoBruto = [Math]::Round($bruto, 2); DespesasPerdas = [Math]::Round($perdas, 2)
            FaturamentoLiquido = [Math]::Round($liquido, 2); CMV = [Math]::Round($cmv, 2); ReceitaOperacionalLiquida = [Math]::Round($rol, 2)
            Opex = $opex; TotalOpex = [Math]::Round($totalOpex, 2); EBITDA = [Math]::Round($ebitda, 2)
            DistribuicaoLucros = [Math]::Round($distrib, 2); Investimentos = [Math]::Round($invest, 2)
            EmprestimosFinanciamentos = [Math]::Round($emprest, 2); ResultadoGeral = [Math]::Round($resultado, 2)
        }
    }

    $dreTodos = @{}
    foreach ($u in $unidadesComConsolidado) { $dreTodos[$u] = Get-DREUnidade -U $u }

    return [PSCustomObject]@{
        Unidades = $unidades; UnidadesComConsolidado = $unidadesComConsolidado
        FaturamentoPorUnidade = $faturamentoPorUnidade
        TotalPorMacroUnidade = $totalPorMacroUnidade
        TotalPorCategoriaUnidade = $totalPorCategoriaUnidade
        DrePorUnidade = $dreTodos
        Periodo = $periodo; DatasDespesa = $datasDespesa
    }
}

function Build-PlanoDetalhadoSheet {
    param($Workbook, [string[]]$Unidades, $TotalPorMacroUnidade, $TotalPorCategoriaUnidade, $FaturamentoPorUnidade, [string]$Periodo)

    $numCols = 1 + $Unidades.Count
    $ws = $Workbook.Worksheets.Add()
    $ws.Name = "Plano Gerencial"
    $ws.Cells.Font.Name = "Arial"
    $branco = Convert-HexToOle "#FFFFFF"
    $corTitulo = Convert-HexToOle "#142A20"
    $corMacroFill = Convert-HexToOle "#143D2B"
    $corHeaderFill = Convert-HexToOle "#143D2B"
    $corDataFill = Convert-HexToOle "#EEF5F0"
    $corFaturamentoFill = Convert-HexToOle "#E3F2E8"

    $row = 1
    $ws.Cells.Item($row, 1) = "Plano Gerencial - Fechamento de Despesas"
    $tRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $tRng.Merge() | Out-Null
    $tRng.Font.Size = 18; $tRng.Font.Bold = $true; $tRng.Font.Color = $corTitulo
    $tRng.HorizontalAlignment = -4108
    $row++
    $ws.Cells.Item($row, 1) = $Periodo
    $sRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $sRng.Merge() | Out-Null
    $sRng.Font.Size = 11; $sRng.Font.Color = Convert-HexToOle "#5B6D62"
    $sRng.HorizontalAlignment = -4108
    $row += 2

    $hdrs = @("Categoria") + $Unidades
    for ($c = 0; $c -lt $numCols; $c++) { $ws.Cells.Item($row, $c + 1) = $hdrs[$c] }
    $hRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $hRng.Font.Bold = $true; $hRng.Font.Color = $branco; $hRng.Interior.Color = $corHeaderFill
    $hRng.Borders.Item(9).LineStyle = 1; $hRng.Borders.Item(9).Weight = 2
    $row++

    $ws.Cells.Item($row, 1) = "FATURAMENTO BRUTO"
    for ($i = 0; $i -lt $Unidades.Count; $i++) {
        $v = 0.0; if ($FaturamentoPorUnidade.ContainsKey($Unidades[$i])) { $v = $FaturamentoPorUnidade[$Unidades[$i]] }
        $ws.Cells.Item($row, $i + 2) = [Math]::Round($v, 2)
    }
    $fRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
    $fRng.Font.Bold = $true; $fRng.Interior.Color = $corFaturamentoFill
    $ws.Range($ws.Cells.Item($row, 2), $ws.Cells.Item($row, $numCols)).NumberFormat = $Script:FormatoMoedaSimples
    $fRng.Borders.Item(9).LineStyle = 1; $fRng.Borders.Item(9).Weight = 2
    $row += 2

    foreach ($macro in $Script:MacroDREOrdemDRE) {
        $ws.Cells.Item($row, 1) = $macro
        for ($i = 0; $i -lt $Unidades.Count; $i++) {
            $k = "$($Unidades[$i])|$macro"
            $v = 0.0; if ($TotalPorMacroUnidade.ContainsKey($k)) { $v = $TotalPorMacroUnidade[$k] }
            $ws.Cells.Item($row, $i + 2) = [Math]::Round($v, 2)
        }
        $mRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
        $mRng.Font.Bold = $true; $mRng.Font.Color = $branco; $mRng.Interior.Color = $corMacroFill
        $ws.Range($ws.Cells.Item($row, 2), $ws.Cells.Item($row, $numCols)).NumberFormat = $Script:FormatoMoedaSimples
        $mRng.Borders.Item(9).LineStyle = 1; $mRng.Borders.Item(9).Weight = 2
        $row++

        $chaveConsolidado = "CONSOLIDADO|"
        $categorias = @($TotalPorCategoriaUnidade.Keys |
            Where-Object { $_.StartsWith($chaveConsolidado) -and $TotalPorCategoriaUnidade[$_].Macro -eq $macro } |
            ForEach-Object { $_.Substring($chaveConsolidado.Length) } | Sort-Object)
        foreach ($cat in $categorias) {
            $ws.Cells.Item($row, 1) = "   $cat"
            for ($i = 0; $i -lt $Unidades.Count; $i++) {
                $kc = "$($Unidades[$i])|$cat"
                $v = 0.0; if ($TotalPorCategoriaUnidade.ContainsKey($kc)) { $v = $TotalPorCategoriaUnidade[$kc].Valor }
                $ws.Cells.Item($row, $i + 2) = [Math]::Round($v, 2)
            }
            $cRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, $numCols))
            $cRng.Interior.Color = $corDataFill
            $ws.Range($ws.Cells.Item($row, 2), $ws.Cells.Item($row, $numCols)).NumberFormat = $Script:FormatoMoedaSimples
            $row++
        }
        $row++
    }

    $ws.Columns.Item(1).ColumnWidth = 42
    for ($c = 2; $c -le $numCols; $c++) { $ws.Columns.Item($c).ColumnWidth = 20 }
    try { $ws.Application.ActiveWindow.DisplayGridlines = $false } catch {}
    return $ws
}

function Build-PlanoResumidoSheet {
    param($Workbook, [string[]]$Unidades, $TotalPorMacroUnidade, $FaturamentoPorUnidade, [string]$Periodo)

    $rows = New-Object System.Collections.Generic.List[object]
    $linha = New-Object System.Collections.Generic.List[object]
    $linha.Add("FATURAMENTO BRUTO") | Out-Null
    foreach ($u in $Unidades) {
        $v = 0.0; if ($FaturamentoPorUnidade.ContainsKey($u)) { $v = $FaturamentoPorUnidade[$u] }
        $linha.Add([Math]::Round($v, 2)) | Out-Null
    }
    $rows.Add($linha.ToArray()) | Out-Null

    foreach ($macro in $Script:MacroDREOrdemDRE) {
        $linha = New-Object System.Collections.Generic.List[object]
        $linha.Add($macro) | Out-Null
        foreach ($u in $Unidades) {
            $k = "$u|$macro"
            $v = 0.0; if ($TotalPorMacroUnidade.ContainsKey($k)) { $v = $TotalPorMacroUnidade[$k] }
            $linha.Add([Math]::Round($v, 2)) | Out-Null
        }
        $rows.Add($linha.ToArray()) | Out-Null
    }

    $headers = @("Categoria") + $Unidades
    $currCols = @(2..($Unidades.Count + 1))
    Write-TitledSheet -Workbook $Workbook -SheetName "Plano Gerencial Resumido" `
        -TitleLines @("PLANO GERENCIAL RESUMIDO — $Periodo") `
        -Headers $headers -Rows $rows -CurrencyColIndexes $currCols `
        -TitleColorHex "#143D2B" -HeaderColorHex "#143D2B" | Out-Null
}

function Build-DRESheet {
    param($Workbook, $DreConsolidado, [string]$Periodo)

    $ptBR = [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    $bruto = $DreConsolidado.FaturamentoBruto
    $linhas = New-Object System.Collections.Generic.List[object]
    $linhas.Add(@("FATURAMENTO BRUTO (+)", $DreConsolidado.FaturamentoBruto)) | Out-Null
    $linhas.Add(@("DESPESAS POR PERDAS (-)", $DreConsolidado.DespesasPerdas)) | Out-Null
    $linhas.Add(@("FATURAMENTO LIQUIDO", $DreConsolidado.FaturamentoLiquido)) | Out-Null
    $linhas.Add(@("CMV (-)", $DreConsolidado.CMV)) | Out-Null
    $linhas.Add(@("RECEITA OPERACIONAL LIQUIDA", $DreConsolidado.ReceitaOperacionalLiquida)) | Out-Null
    foreach ($m in $Script:MacroDREOpex) { $linhas.Add(@("$m (-)", $DreConsolidado.Opex[$m])) | Out-Null }
    $linhas.Add(@("EBITDA", $DreConsolidado.EBITDA)) | Out-Null
    $linhas.Add(@("DISTRIBUICAO DE LUCROS (-)", $DreConsolidado.DistribuicaoLucros)) | Out-Null
    $linhas.Add(@("INVESTIMENTOS (-)", $DreConsolidado.Investimentos)) | Out-Null
    $linhas.Add(@("EMPRESTIMOS E FINANCIAMENTOS (-)", $DreConsolidado.EmprestimosFinanciamentos)) | Out-Null
    $linhas.Add(@("RESULTADO GERAL", $DreConsolidado.ResultadoGeral)) | Out-Null

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($l in $linhas) {
        $pct = if ($bruto -ne 0) { ($l[1] / $bruto) * 100 } else { 0.0 }
        $pctStr = $pct.ToString("N2", $ptBR) + "%"
        $rows.Add(@($l[0], [Math]::Round($l[1], 2), $pctStr)) | Out-Null
    }
    Write-TitledSheet -Workbook $Workbook -SheetName "DRE" `
        -TitleLines @("DRE — $Periodo") `
        -Headers @("Operação", "Valor", "% AV") -Rows $rows -CurrencyColIndexes @(2) `
        -TitleColorHex "#143D2B" -HeaderColorHex "#143D2B" | Out-Null
}

function Build-PremissasChecksFechamentoSheet {
    param($Workbook, $MapaMacroDRE, $DespesaRecords, $FaturamentoPorUnidade, $TotalPorMacroUnidade, [string]$Periodo, [datetime[]]$DatasDespesa)

    $ws = $Workbook.Worksheets.Add()
    $ws.Name = "Premissas e Checks"
    $ws.Cells.Font.Name = "Arial"
    $branco = Convert-HexToOle "#FFFFFF"
    $corHeaderFill = Convert-HexToOle "#143D2B"

    $ws.Cells.Item(1, 1) = "PREMISSAS E CONTROLES — $Periodo"
    $tRng = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, 4))
    $tRng.Merge() | Out-Null
    $tRng.Font.Bold = $true; $tRng.Font.Size = 14; $tRng.Font.Color = $branco
    $tRng.Interior.Color = Convert-HexToOle "#143D2B"

    $row = 3
    $hdrs = @("CHECK", "DELTA / VALOR", "STATUS", "OBSERVAÇÃO")
    for ($c = 0; $c -lt 4; $c++) { $ws.Cells.Item($row, $c + 1) = $hdrs[$c] }
    $hRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, 4))
    $hRng.Font.Bold = $true; $hRng.Font.Color = $branco; $hRng.Interior.Color = $corHeaderFill
    $row++

    $despesaTotal = [Math]::Round((($DespesaRecords | Measure-Object -Property Valor -Sum).Sum), 2)
    $planoTotal = 0.0
    foreach ($m in $Script:MacroDREOrdemDRE) {
        $k = "CONSOLIDADO|$m"
        if ($TotalPorMacroUnidade.ContainsKey($k)) { $planoTotal += $TotalPorMacroUnidade[$k] }
    }
    $deltaDespesas = [Math]::Round($despesaTotal - $planoTotal, 2)
    $naoMapeados = @($DespesaRecords | Where-Object { $_.MacroDRE -eq "NÃO MAPEADO" })
    $totalReceita = 0.0; if ($FaturamentoPorUnidade.ContainsKey("CONSOLIDADO")) { $totalReceita = $FaturamentoPorUnidade["CONSOLIDADO"] }

    # Lista de List[object], nao array-de-arrays: um "@( @(...) @(...) )" bare desmancha os
    # arrays internos no stream de saida (cada elemento vira um item solto), entao $chk[$c]
    # acabava indexando dentro da STRING (virando codigo de caractere) em vez do array da linha.
    $checks = New-Object System.Collections.Generic.List[object]
    $checks.Add(@("Despesas x Plano", "$deltaDespesas", $(if ([Math]::Abs($deltaDespesas) -lt 0.01) { "PASS" } else { "FAIL" }), "Categorias não mapeadas ficam fora do plano - deve reconciliar em centavos")) | Out-Null
    $checks.Add(@("Categorias não mapeadas", "$($naoMapeados.Count)", $(if ($naoMapeados.Count -eq 0) { "PASS" } else { "FAIL" }), "Deve ser zero - edite o mapeamento na aba 2 do app")) | Out-Null
    $checks.Add(@("Receita informada", "R`$ $totalReceita", $(if ($totalReceita -gt 0) { "PASS" } else { "PENDENTE" }), "Necessária para EBITDA e Resultado Geral corretos")) | Out-Null
    $checks.Add(@("Período da base", $Periodo, $(if ($DatasDespesa.Count -gt 0) { "OK" } else { "FAIL" }), "Datas encontradas na planilha de despesas")) | Out-Null
    foreach ($chk in $checks) {
        for ($c = 0; $c -lt 4; $c++) { $ws.Cells.Item($row, $c + 1) = $chk[$c] }
        $row++
    }

    $row += 2
    $ws.Cells.Item($row, 1) = "Descrição C. Gerencial"; $ws.Cells.Item($row, 2) = "Macro DRE"
    $mhRng = $ws.Range($ws.Cells.Item($row, 1), $ws.Cells.Item($row, 2))
    $mhRng.Font.Bold = $true; $mhRng.Font.Color = $branco; $mhRng.Interior.Color = $corHeaderFill
    $row++
    foreach ($k in ($MapaMacroDRE.Keys | Sort-Object { $MapaMacroDRE[$_] }, { $_ })) {
        $ws.Cells.Item($row, 1) = $k
        $ws.Cells.Item($row, 2) = $MapaMacroDRE[$k]
        $row++
    }

    $ws.Columns.Item(1).ColumnWidth = 40
    for ($c = 2; $c -le 4; $c++) { $ws.Columns.Item($c).ColumnWidth = 22 }
    return $ws
}

function Export-RelatorioFechamento {
    param($ExcelApp, $Resultado, $DespesaRecords, $ReceitaRecords, $MapaMacroDRE, [string]$OutputPath)

    $ExcelApp.DisplayAlerts = $false
    $wb = $ExcelApp.Workbooks.Add()
    while ($wb.Worksheets.Count -gt 1) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }
    $sheetOriginal = $wb.Worksheets.Item(1)

    Build-PlanoDetalhadoSheet -Workbook $wb -Unidades $Resultado.UnidadesComConsolidado -TotalPorMacroUnidade $Resultado.TotalPorMacroUnidade -TotalPorCategoriaUnidade $Resultado.TotalPorCategoriaUnidade -FaturamentoPorUnidade $Resultado.FaturamentoPorUnidade -Periodo $Resultado.Periodo | Out-Null

    Build-PlanoResumidoSheet -Workbook $wb -Unidades $Resultado.UnidadesComConsolidado -TotalPorMacroUnidade $Resultado.TotalPorMacroUnidade -FaturamentoPorUnidade $Resultado.FaturamentoPorUnidade -Periodo $Resultado.Periodo

    Build-DRESheet -Workbook $wb -DreConsolidado $Resultado.DrePorUnidade["CONSOLIDADO"] -Periodo $Resultado.Periodo

    Build-PremissasChecksFechamentoSheet -Workbook $wb -MapaMacroDRE $MapaMacroDRE -DespesaRecords $DespesaRecords -FaturamentoPorUnidade $Resultado.FaturamentoPorUnidade -TotalPorMacroUnidade $Resultado.TotalPorMacroUnidade -Periodo $Resultado.Periodo -DatasDespesa $Resultado.DatasDespesa | Out-Null

    $rowsDesp = New-Object System.Collections.Generic.List[object]
    foreach ($r in ($DespesaRecords | Sort-Object Unidade, Data)) {
        $rowsDesp.Add(@($r.Unidade, $r.Data, $r.DescricaoGerencial, $r.MacroDRE, [Math]::Round($r.Valor, 2), $r.Posicao, $r.DiasAtraso, $r.ArquivoOrigem)) | Out-Null
    }
    Write-SheetFromRows -Workbook $wb -SheetName "Base Despesas" -Headers @("Unidade", "Data", "Descrição C. Gerencial", "Macro DRE", "Valor", "Posição", "Dias Atraso", "Arquivo") -Rows $rowsDesp -DateColIndexes @(2) -CurrencyColIndexes @(5) | Out-Null

    $rowsRec = New-Object System.Collections.Generic.List[object]
    foreach ($r in ($ReceitaRecords | Sort-Object Unidade, Data)) {
        $rowsRec.Add(@($r.Unidade, $r.Data, [Math]::Round($r.Valor, 2), $r.ArquivoOrigem)) | Out-Null
    }
    Write-SheetFromRows -Workbook $wb -SheetName "Base Receita" -Headers @("Unidade", "Data", "Valor", "Arquivo") -Rows $rowsRec -DateColIndexes @(2) -CurrencyColIndexes @(3) | Out-Null

    $sheetOriginal.Delete()
    $wb.Worksheets.Item("Plano Gerencial").Activate()
    $wb.Worksheets.Item("Plano Gerencial").Range("A1").Select() | Out-Null

    $wb.SaveAs($OutputPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
    $wb.Close($false)
    return $OutputPath
}

# ============================================================================
# INTERFACE GRAFICA
# ============================================================================
function Add-BarraVoltarHub {
    # Barra fixa no topo, presente em toda tela aberta a partir de outra (modulo ou tela de
    # cards aninhada). Navigate-Back troca o conteudo do content-root de volta pra tela
    # anterior (empilhada em Navigate-Forward) dentro da mesma janela unica - nao ha mais um
    # Form proprio pra fechar aqui (ver Start-App).
    param($Form)

    # Padrao BackButton: variante ghost do Button - texto brand-600 sobre surface, sem
    # preenchimento nem borda, pra nao competir com a acao primaria da tela.
    $panelTop = New-Object System.Windows.Forms.Panel
    $panelTop.Dock = "Top"
    $panelTop.Height = 44
    $panelTop.BackColor = $Script:DS.Surface
    $Form.Controls.Add($panelTop)

    $btnVoltar = New-Object System.Windows.Forms.Button
    $btnVoltar.Text = [char]0x2039 + " Voltar"
    $btnVoltar.Font = DSFont "button-label"
    $btnVoltar.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnVoltar.FlatAppearance.BorderSize = 0
    $btnVoltar.FlatAppearance.MouseOverBackColor = $Script:DS.Surface
    $btnVoltar.FlatAppearance.MouseDownBackColor = $Script:DS.Surface
    $btnVoltar.BackColor = $Script:DS.Surface
    $btnVoltar.ForeColor = $Script:DS.Brand600
    $btnVoltar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnVoltar.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnVoltar.AutoSize = $true
    $btnVoltar.Padding = New-Object System.Windows.Forms.Padding 0
    $btnVoltar.Location = New-Object System.Drawing.Point $Script:DSSpace8, 10
    $btnVoltar.Add_Click({ Navigate-Back })
    $panelTop.Controls.Add($btnVoltar)

    $upd = Get-AtualizacaoInfoCache
    if ($upd.Disponivel) {
        $lblUpd = New-DSLinkAtualizacao -Upd $upd
        $panelTop.Controls.Add($lblUpd)
        # Posiciona encostado na borda direita do painel (espacamento space-8 = 32px); reflow
        # no Resize pra continuar alinhado se a janela for redimensionada. Valor 32 fixo em vez
        # de $Script:DSSpace8: referencia direta a variavel script-scoped dentro de um closure
        # de evento assincrono (Resize dispara pelo layout engine, nao na hora) voltava nula no
        # exe compilado - mesmo bug ja visto em Enable-ModuleTabsStyling.
        $panelTop.Add_Resize({
            $lblUpd.Location = New-Object System.Drawing.Point(($panelTop.Width - $lblUpd.Width - 32), 13)
        }.GetNewClosure())
        $lblUpd.Location = New-Object System.Drawing.Point(($panelTop.Width - $lblUpd.Width - 32), 13)
    }
}

function New-ConciliacaoPanel {
    # Retorna um Panel (Dock=Fill) pronto pra entrar no content-root da janela unica do app
    # (ver Navigate-Forward/Navigate-Back) - nao e mais um Form proprio: a janela em si
    # ($Script:MainForm) e criada uma unica vez em Start-App e nunca fecha/reabre durante a
    # navegacao, so o conteudo dentro dela troca. $mainForm (capturado uma vez aqui, local)
    # e usado so pro que continua sendo responsabilidade da JANELA (cursor de espera,
    # Refresh, dono de OpenFileDialog/SaveFileDialog) - nunca $Script:MainForm direto dentro
    # de um closure de evento assincrono (mesmo bug ja documentado em
    # Enable-ModuleTabsStyling).
    $mainForm = $Script:MainForm
    $cfg = Load-AppConfig

    $form = New-Object System.Windows.Forms.Panel
    $form.Dock = "Fill"
    $form.BackColor = $Script:DS.SurfacePage

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = "Fill"
    $tabs.Font = DSFont "button-label"
    $form.Controls.Add($tabs)
    Enable-ModuleTabsStyling -TabControl $tabs

    # Ordem de Dock=Top importa (ver nota em Add-DSTopo/Add-BarraVoltarHub): Voltar adicionado
    # primeiro, Topo depois - o ultimo Dock=Top adicionado fica mais externo/no topo, entao
    # o bloco icone+titulo fica no topo da janela, com o Voltar logo abaixo dele.
    Add-BarraVoltarHub -Form $form
    Add-DSTopo -Form $form -Titulo "Conciliação de Vendas" | Out-Null

    # Texto das abas sem numero (o circulo numerado do ModuleTabs ja mostra a etapa).
    $tabArquivos = New-Object System.Windows.Forms.TabPage
    $tabArquivos.Text = "Arquivos"
    $tabArquivos.BackColor = $Script:DS.Surface
    $tabs.TabPages.Add($tabArquivos)

    $tabMapa = New-Object System.Windows.Forms.TabPage
    $tabMapa.Text = "Mapeamento de unidade"
    $tabMapa.BackColor = $Script:DS.Surface
    $tabs.TabPages.Add($tabMapa)

    $tabResultado = New-Object System.Windows.Forms.TabPage
    $tabResultado.Text = "Resultado"
    $tabResultado.BackColor = $Script:DS.Surface
    $tabs.TabPages.Add($tabResultado)

    # ---------- TAB 1: ARQUIVOS ----------
    # Painel inferior fixo (sempre visivel) com o botao de analisar, e um painel de
    # conteudo com rolagem automatica acima dele - assim o botao nunca fica escondido
    # e, em telas menores, da para rolar ate os arquivos/campos que nao couberem.
    $panelArquivosBottom = New-Object System.Windows.Forms.Panel
    $panelArquivosBottom.Dock = "Bottom"
    $panelArquivosBottom.Height = 60
    $tabArquivos.Controls.Add($panelArquivosBottom)

    $panelArquivos = New-Object System.Windows.Forms.Panel
    $panelArquivos.Dock = "Fill"
    $panelArquivos.BackColor = $Script:DS.Surface
    $panelArquivos.AutoScroll = $true
    $tabArquivos.Controls.Add($panelArquivos)
    $panelArquivos.BringToFront()

    # Painel intermediario de altura fixa (cabe os dois grupos de arquivo sem cortar) dentro
    # do painel com AutoScroll: ancorar Right um filho DIRETO de um painel AutoScroll cria um
    # loop de realimentacao conhecido do WinForms (o painel recalcula a area de scroll a
    # partir do filho, o filho ancorado recalcula a largura a partir do painel, e a largura
    # dispara sem controle). Sincronizar a largura deste painel intermediario a mao, no Resize
    # do painel de fora, evita o loop porque so anda numa direcao (pai -> filho, nunca volta);
    # os grupos dentro dele usam Anchor=Right normalmente, sem risco, porque ESTE painel nao
    # tem AutoScroll proprio.
    $panelArquivosConteudo = New-Object System.Windows.Forms.Panel
    $panelArquivosConteudo.Location = New-Object System.Drawing.Point 0, 0
    $panelArquivosConteudo.Height = 680
    # Largura inicial FIXA (950 = 930 do GroupBox classico + 20 de margem), nao lida de
    # $panelArquivos.ClientSize.Width: nesse ponto da construcao o Form ainda nao passou pelo
    # layout de verdade, entao ClientSize.Width vem um valor pequeno/de rascunho (cai no piso
    # de 700) - GroupBox/grid/botoes (abaixo, com posicoes em pixel fixo desenhadas pra caber
    # num GroupBox de 930) ancoravam relativo a esse valor ERRADO, e o "espaco preservado pelo
    # Anchor" saia negativo (grid mais largo que o proprio GroupBox). Isso so aparecia visivelmente
    # depois, ao redimensionar pra bem largo (os botoes acabavam posicionados fora da area
    # visivel do GroupBox) - bug real reportado pelo usuario. Com a largura inicial batendo
    # com o design classico, o Anchor de cada filho comeca com a folga certa e escala
    # corretamente dali em diante.
    $panelArquivosConteudo.Width = 950
    $panelArquivosConteudo.BackColor = $Script:DS.Surface
    $panelArquivos.Controls.Add($panelArquivosConteudo)
    $panelArquivos.Add_Resize({
        param($s, $e)
        $panelArquivosConteudo.Width = [Math]::Max($s.ClientSize.Width, 700)
    }.GetNewClosure())

    # Campos de senha FIXOS por banco (C6 / Sicredi), nao mais genericos "banco 1/banco 2"
    # relinkados dinamicamente conforme a ordem em que os arquivos eram adicionados ao grid -
    # essa indirecao (qual campo pertencia a qual banco podia mudar de acordo com a ordem dos
    # arquivos) confundia o usuario sobre qual senha ia pra qual campo e ja causou um caso real
    # de senha indo pro banco errado. Agora "Senha C6" e "Senha Sicredi" sao sempre o mesmo
    # campo, sem excecao.
    # Espacamento generoso de proposito (folgas maiores que $Script:DSSpace4/6 puros em
    # alguns pontos): usuario reportou os textos/controles muito colados uns nos outros em
    # todas as abas - aqui e no resto desta aba, toda folga vertical entre elementos foi
    # aumentada (era metade disso ou menos).
    # So o C6 exige senha (planilha protegida) - o Sicredi nao (ver Read-SicrediFile: sempre
    # chamado com senha vazia, abaixo). Um unico campo de senha, entao.
    $y = $Script:DSSpace4
    $lblSenhaC6 = New-Object System.Windows.Forms.Label
    $lblSenhaC6.Text = "Senha C6:"
    $lblSenhaC6.Font = DSFont "body"
    $lblSenhaC6.ForeColor = $Script:DS.Ink
    $lblSenhaC6.Location = New-Object System.Drawing.Point($Script:DSSpace4, $y)
    $lblSenhaC6.AutoSize = $true
    $panelArquivosConteudo.Controls.Add($lblSenhaC6)
    $txtSenhaC6 = New-Object System.Windows.Forms.TextBox
    $txtSenhaC6.Location = New-Object System.Drawing.Point(330, ($y - 3))
    $txtSenhaC6.Width = 150
    $txtSenhaC6.Font = DSFont "body"
    if ($cfg.SenhasBanco.ContainsKey("C6")) { $txtSenhaC6.Text = $cfg.SenhasBanco["C6"] }
    $panelArquivosConteudo.Controls.Add($txtSenhaC6)
    $y += 44

    function New-FileGroup {
        param($Parent, [string]$Title, [int]$Top, [int]$Height)
        $grp = New-Object System.Windows.Forms.GroupBox
        $grp.Text = $Title
        $grp.Location = New-Object System.Drawing.Point(10, $Top)
        $grp.Size = New-Object System.Drawing.Size(($Parent.Width - 20), $Height)
        # Anchor com "Right" seguro aqui porque $Parent e o painel intermediario de largura
        # fixa (nao o painel com AutoScroll em si - ver nota em panelArquivosConteudo), entao
        # nao ha o loop de realimentacao AutoScroll+Anchor do WinForms.
        $grp.Anchor = "Top,Left,Right"
        $Parent.Controls.Add($grp)

        $grid = New-Object System.Windows.Forms.DataGridView
        # Y logo abaixo da faixa do titulo do GroupBox (DisplayRectangle.Top acompanha o tamanho
        # real da fonte - com zoom do Windows em 125%/150% um Y fixo encostava a grade no titulo).
        $yConteudo = $grp.DisplayRectangle.Top + $Script:DSSpace1
        # Largura dos botoes = texto REAL do maior rotulo (na fonte do botao) + folga dos dois
        # lados - com largura fixa "Remover selecionado" saia cortado ("Remover sel...") no
        # zoom de 150% do Windows. O resto da largura do grupo fica pra grade.
        $textoBotaoMaior = [System.Windows.Forms.TextRenderer]::MeasureText("Remover selecionado", (DSFont "button-label"))
        $larguraBotoes = [Math]::Max(150, $textoBotaoMaior.Width + (2 * $Script:DSSpace4))
        $xBotoes = ($Parent.Width - 20) - 10 - $larguraBotoes
        $grid.Location = New-Object System.Drawing.Point(10, $yConteudo)
        $grid.Size = New-Object System.Drawing.Size(($xBotoes - 10 - 10), ($Height - $yConteudo - 10))
        $grid.Anchor = "Top,Left,Right,Bottom"
        $grid.AllowUserToAddRows = $false
        $grid.AllowUserToDeleteRows = $false
        $grid.SelectionMode = "FullRowSelect"
        $grid.RowHeadersVisible = $false
        $grid.AllowDrop = $true
        $grid.ShowCellToolTips = $true
        Set-DSGridStyle -Grid $grid
        $grid.Add_DragEnter({
            param($s, $e)
            if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy }
            else { $e.Effect = [System.Windows.Forms.DragDropEffects]::None }
        })
        $grid.Add_CellToolTipTextNeeded({
            param($s, $e)
            if ($e.RowIndex -ge 0 -and $s.Columns[$e.ColumnIndex].Name -eq "Arquivo") {
                $e.ToolTipText = "$($s.Rows[$e.RowIndex].Cells['ArquivoCompleto'].Value)"
            }
        })

        # Coluna visivel mostra so o nome do arquivo (caminho completo fica numa coluna
        # oculta) para nao espremer as outras colunas com caminhos longos.
        $colArquivo = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $colArquivo.Name = "Arquivo"
        $colArquivo.HeaderText = "Arquivo"
        $colArquivo.ReadOnly = $true
        $colArquivo.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
        $colArquivo.MinimumWidth = 200
        $grid.Columns.Add($colArquivo) | Out-Null

        $grp.Controls.Add($grid)

        $btnAdd = New-DSBotaoSecundario -Texto "Adicionar..."
        $btnAdd.Location = New-Object System.Drawing.Point($xBotoes, $yConteudo)
        $btnAdd.Size = New-Object System.Drawing.Size($larguraBotoes, 34)
        $btnAdd.Anchor = "Top,Right"
        $grp.Controls.Add($btnAdd)

        $btnRemove = New-DSBotaoSecundario -Texto "Remover selecionado"
        $btnRemove.Location = New-Object System.Drawing.Point($xBotoes, ($yConteudo + 34 + $Script:DSSpace2))
        $btnRemove.Size = New-Object System.Drawing.Size($larguraBotoes, 34)
        $btnRemove.Anchor = "Top,Right"
        $grp.Controls.Add($btnRemove)

        return [PSCustomObject]@{ Group = $grp; Grid = $grid; BtnAdd = $btnAdd; BtnRemove = $btnRemove }
    }

    $sisPanel = New-FileGroup -Parent $panelArquivosConteudo -Title "Arquivos do Sistema (Vendas Sistema) - arraste os arquivos aqui ou use o botao" -Top $y -Height 180
    $colUnidade = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $colUnidade.Name = "Unidade"
    $colUnidade.HeaderText = "Unidade"
    $colUnidade.Width = 130
    $colUnidade.Items.AddRange(@("MOOCA", "VILA MOURA"))
    $sisPanel.Grid.Columns.Add($colUnidade) | Out-Null
    $colCompletoSis = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colCompletoSis.Name = "ArquivoCompleto"; $colCompletoSis.Visible = $false
    $sisPanel.Grid.Columns.Add($colCompletoSis) | Out-Null
    $y += 180 + $Script:DSSpace6

    # Um painel proprio por banco (em vez de um painel unico com deteccao pelo nome do
    # arquivo): cada grid so recebe arquivos do banco correspondente, entao o banco de cada
    # arquivo fica implicito em qual painel ele foi colocado - sem coluna "Banco" pra editar
    # nem deteccao por nome de arquivo pra acertar.
    $c6Panel = New-FileGroup -Parent $panelArquivosConteudo -Title "Arquivos C6 - arraste os arquivos aqui ou use o botao" -Top $y -Height 180
    $colCompletoC6 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colCompletoC6.Name = "ArquivoCompleto"; $colCompletoC6.Visible = $false
    $c6Panel.Grid.Columns.Add($colCompletoC6) | Out-Null
    $y += 180 + $Script:DSSpace6

    $sicrediPanel = New-FileGroup -Parent $panelArquivosConteudo -Title "Arquivos Sicredi - arraste os arquivos aqui ou use o botao" -Top $y -Height 180
    $colCompletoSicredi = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colCompletoSicredi.Name = "ArquivoCompleto"; $colCompletoSicredi.Visible = $false
    $sicrediPanel.Grid.Columns.Add($colCompletoSicredi) | Out-Null
    $y += 180 + $Script:DSSpace6

    $panelArquivosBottom.BackColor = $Script:DS.Surface
    $btnAnalisar = New-DSBotao -Texto "Analisar arquivos >>" -Variante "primary"
    $btnAnalisar.Location = New-Object System.Drawing.Point($Script:DSSpace4, 12)
    $btnAnalisar.Size = New-Object System.Drawing.Size(220, 36)
    $panelArquivosBottom.Controls.Add($btnAnalisar)

    $lblStatusArquivos = New-Object System.Windows.Forms.Label
    $lblStatusArquivos.Font = DSFont "caption"
    $lblStatusArquivos.ForeColor = $Script:DS.InkMuted
    $lblStatusArquivos.Location = New-Object System.Drawing.Point(($Script:DSSpace4 + 220 + $Script:DSSpace6), 5)
    $lblStatusArquivos.Size = New-Object System.Drawing.Size(750, 50)
    $lblStatusArquivos.Anchor = "Top,Left,Right,Bottom"
    $panelArquivosBottom.Controls.Add($lblStatusArquivos)

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Excel (*.xlsx;*.xls)|*.xlsx;*.xls|Todos os arquivos (*.*)|*.*"
    $ofd.Multiselect = $true

    $sisPanel.BtnAdd.Add_Click({
        try {
            $ofd.Title = "Selecionar arquivos do Sistema"
            $r = $ofd.ShowDialog($mainForm)
            if ($r -eq [System.Windows.Forms.DialogResult]::OK) { Add-ArquivosAoGrid -Grid $sisPanel.Grid -Paths $ofd.FileNames -DetectUnidade $true }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao abrir o seletor de arquivos:`n`n$($_.Exception.ToString())", "Erro - Adicionar (Sistema)") | Out-Null
        }
    }.GetNewClosure())
    $sisPanel.BtnRemove.Add_Click({
        foreach ($row in @($sisPanel.Grid.SelectedRows)) { $sisPanel.Grid.Rows.Remove($row) }
    }.GetNewClosure())
    $sisPanel.Grid.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete) { foreach ($row in @($sisPanel.Grid.SelectedRows)) { $sisPanel.Grid.Rows.Remove($row) } }
    }.GetNewClosure())
    $sisPanel.Grid.Add_DragDrop({
        param($s, $e)
        $paths = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Add-ArquivosAoGrid -Grid $sisPanel.Grid -Paths $paths -DetectUnidade $true
    }.GetNewClosure())

    $c6Panel.BtnAdd.Add_Click({
        try {
            $ofd.Title = "Selecionar arquivo(s) do C6"
            $r = $ofd.ShowDialog($mainForm)
            if ($r -eq [System.Windows.Forms.DialogResult]::OK) { Add-ArquivosAoGrid -Grid $c6Panel.Grid -Paths $ofd.FileNames }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao abrir o seletor de arquivos:`n`n$($_.Exception.ToString())", "Erro - Adicionar (C6)") | Out-Null
        }
    }.GetNewClosure())
    $c6Panel.BtnRemove.Add_Click({
        foreach ($row in @($c6Panel.Grid.SelectedRows)) { $c6Panel.Grid.Rows.Remove($row) }
    }.GetNewClosure())
    $c6Panel.Grid.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
            foreach ($row in @($c6Panel.Grid.SelectedRows)) { $c6Panel.Grid.Rows.Remove($row) }
        }
    }.GetNewClosure())
    $c6Panel.Grid.Add_DragDrop({
        param($s, $e)
        $paths = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Add-ArquivosAoGrid -Grid $c6Panel.Grid -Paths $paths
    }.GetNewClosure())

    $sicrediPanel.BtnAdd.Add_Click({
        try {
            $ofd.Title = "Selecionar arquivo(s) do Sicredi"
            $r = $ofd.ShowDialog($mainForm)
            if ($r -eq [System.Windows.Forms.DialogResult]::OK) { Add-ArquivosAoGrid -Grid $sicrediPanel.Grid -Paths $ofd.FileNames }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao abrir o seletor de arquivos:`n`n$($_.Exception.ToString())", "Erro - Adicionar (Sicredi)") | Out-Null
        }
    }.GetNewClosure())
    $sicrediPanel.BtnRemove.Add_Click({
        foreach ($row in @($sicrediPanel.Grid.SelectedRows)) { $sicrediPanel.Grid.Rows.Remove($row) }
    }.GetNewClosure())
    $sicrediPanel.Grid.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
            foreach ($row in @($sicrediPanel.Grid.SelectedRows)) { $sicrediPanel.Grid.Rows.Remove($row) }
        }
    }.GetNewClosure())
    $sicrediPanel.Grid.Add_DragDrop({
        param($s, $e)
        $paths = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Add-ArquivosAoGrid -Grid $sicrediPanel.Grid -Paths $paths
    }.GetNewClosure())

    # ---------- TAB 2: MAPEAMENTO ----------
    # Painel inferior fixo (Dock=Bottom) com o botao "Gerar" - fica sempre visivel,
    # independente do tamanho da janela/resolucao. A grade ocupa o resto (Dock=Fill)
    # e tem sua propria rolagem (vertical e horizontal) para as colunas nao ficarem espremidas.
    $panelMapaBottom = New-Object System.Windows.Forms.Panel
    $panelMapaBottom.Dock = "Bottom"
    $panelMapaBottom.Height = 60
    $tabMapa.Controls.Add($panelMapaBottom)

    # Texto explicativo quebrado em linhas (AutoSize=$false; o padrao do Label, AutoSize=$true,
    # deixa uma linha so que passa da borda da janela) e faixa do topo com a altura MEDIDA do
    # texto na menor largura possivel (700) - ver nota sobre zoom do Windows em
    # New-FechamentoPanel.
    $textoMapa = "Confirme a unidade de cada terminal/estabelecimento identificado nos arquivos de banco. Valores sugeridos com base no historico salvo."
    $fonteMapa = DSFont "caption"
    $alturaTextoMapa = [System.Windows.Forms.TextRenderer]::MeasureText($textoMapa, $fonteMapa, (New-Object System.Drawing.Size((700 - (2 * $Script:DSSpace4)), 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height

    $panelMapaTop = New-Object System.Windows.Forms.Panel
    $panelMapaTop.Dock = "Top"
    $panelMapaTop.Height = $alturaTextoMapa + (2 * $Script:DSSpace2)
    $panelMapaTop.BackColor = $Script:DS.Surface
    $tabMapa.Controls.Add($panelMapaTop)

    $lblMapa = New-Object System.Windows.Forms.Label
    $lblMapa.Text = $textoMapa
    $lblMapa.Font = $fonteMapa
    $lblMapa.ForeColor = $Script:DS.InkMuted
    $lblMapa.AutoSize = $false
    $lblMapa.Location = New-Object System.Drawing.Point($Script:DSSpace4, $Script:DSSpace2)
    $lblMapa.Size = New-Object System.Drawing.Size(950, $alturaTextoMapa)
    $panelMapaTop.Controls.Add($lblMapa)
    # Largura acompanhada a mao no Resize (em vez de Anchor=Right): o painel Dock=Top nasce com
    # largura provisoria, e a folga do Anchor ficaria negativa (rotulo com ~1800px, texto
    # cortado na borda da janela) - ver [Anchor gap locked at parenting time].
    $margemMapa = $Script:DSSpace4
    $panelMapaTop.Add_Resize({
        param($s, $e)
        $lblMapa.Width = [Math]::Max(200, $s.ClientSize.Width - (2 * $margemMapa))
    }.GetNewClosure())

    $gridMapa = New-Object System.Windows.Forms.DataGridView
    $gridMapa.Dock = "Fill"
    Set-DSGridStyle -Grid $gridMapa
    $gridMapa.AllowUserToAddRows = $false
    $gridMapa.AllowUserToDeleteRows = $false
    $gridMapa.RowHeadersVisible = $false
    $gridMapa.AutoSizeColumnsMode = "None"
    $gridMapa.Columns.Add("Origem", "Origem") | Out-Null
    $gridMapa.Columns.Add("Terminal", "Terminal / Estabelecimento") | Out-Null
    $gridMapa.Columns.Add("Qtd", "Qtd. registros") | Out-Null
    $gridMapa.Columns.Add("Total", "Valor total (aprovado)") | Out-Null
    $colUnidadeMapa = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $colUnidadeMapa.Name = "Unidade"
    $colUnidadeMapa.HeaderText = "Unidade"
    $colUnidadeMapa.Items.AddRange(@("MOOCA", "VILA MOURA"))
    $gridMapa.Columns.Add($colUnidadeMapa) | Out-Null
    # Larguras desenhadas pra 100% de zoom, escaladas pelo DPI real (fonte e cabecalho crescem
    # no zoom do Windows; larguras fixas cortavam "Terminal / Estabelecimento" etc.).
    $gEscala = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $escalaDpi = [Math]::Max(1.0, $gEscala.DpiX / 96.0)
    $gEscala.Dispose()
    $gridMapa.Columns["Origem"].Width = [int](90 * $escalaDpi)
    $gridMapa.Columns["Terminal"].Width = [int](240 * $escalaDpi)
    $gridMapa.Columns["Qtd"].Width = [int](120 * $escalaDpi)
    $gridMapa.Columns["Total"].Width = [int](170 * $escalaDpi)
    # Ultima coluna preenche o que sobrar (com piso), em vez de largura fixa que empurrava
    # "Unidade" pra fora da janela e forcava rolagem horizontal.
    $gridMapa.Columns["Unidade"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $gridMapa.Columns["Unidade"].MinimumWidth = [int](150 * $escalaDpi)
    foreach ($cn in @("Origem", "Terminal", "Qtd", "Total")) { $gridMapa.Columns[$cn].ReadOnly = $true }
    $tabMapa.Controls.Add($gridMapa)
    $gridMapa.BringToFront()

    $panelMapaBottom.BackColor = $Script:DS.Surface
    $btnGerar = New-DSBotao -Texto "Gerar relatorio de conciliacao >>" -Variante "primary"
    $btnGerar.Location = New-Object System.Drawing.Point($Script:DSSpace4, 12)
    $btnGerar.Size = New-Object System.Drawing.Size(260, 36)
    $btnGerar.Enabled = $false
    $panelMapaBottom.Controls.Add($btnGerar)

    $lblStatusMapa = New-Object System.Windows.Forms.Label
    $lblStatusMapa.Font = DSFont "caption"
    $lblStatusMapa.ForeColor = $Script:DS.InkMuted
    $lblStatusMapa.Location = New-Object System.Drawing.Point(($Script:DSSpace4 + 260 + $Script:DSSpace6), 5)
    $lblStatusMapa.Size = New-Object System.Drawing.Size(750, 50)
    $lblStatusMapa.Anchor = "Top,Left,Right,Bottom"
    $panelMapaBottom.Controls.Add($lblStatusMapa)

    # ---------- TAB 3: RESULTADO ----------
    $panelResultBottom = New-Object System.Windows.Forms.Panel
    $panelResultBottom.Dock = "Bottom"
    $panelResultBottom.Height = 50
    $panelResultBottom.BackColor = $Script:DS.Surface
    $tabResultado.Controls.Add($panelResultBottom)

    $txtResultado = New-Object System.Windows.Forms.TextBox
    $txtResultado.Multiline = $true
    $txtResultado.ScrollBars = "Vertical"
    $txtResultado.ReadOnly = $true
    $txtResultado.BackColor = $Script:DS.Surface
    $txtResultado.ForeColor = $Script:DS.Ink
    $txtResultado.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtResultado.Dock = "Fill"
    $tabResultado.Controls.Add($txtResultado)
    $txtResultado.BringToFront()

    $btnAbrirRelatorio = New-DSBotao -Texto "Abrir relatorio gerado" -Variante "primary"
    $btnAbrirRelatorio.Location = New-Object System.Drawing.Point($Script:DSSpace4, 8)
    $btnAbrirRelatorio.Size = New-Object System.Drawing.Size(220, 36)
    $btnAbrirRelatorio.Enabled = $false
    $panelResultBottom.Controls.Add($btnAbrirRelatorio)

    # ---------- ESTADO ----------
    $state = [PSCustomObject]@{
        Sistema = $null
        Banco = $null
        RelatorioPath = $null
    }

    # ---------- ACAO: ANALISAR ARQUIVOS ----------
    $btnAnalisar.Add_Click({
        if ($sisPanel.Grid.Rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Adicione ao menos um arquivo do Sistema.", "Atencao") | Out-Null
            return
        }
        foreach ($row in $sisPanel.Grid.Rows) {
            if (-not $row.Cells["Unidade"].Value) {
                [System.Windows.Forms.MessageBox]::Show("Defina a unidade (Mooca/Vila Moura) de todos os arquivos do Sistema.", "Atencao") | Out-Null
                return
            }
        }
        # So o C6 exige senha (ver Read-SicrediFile: sempre lido com senha vazia) - valida
        # antes de tentar abrir qualquer arquivo: sem a senha certa, o Excel.Workbooks.Open
        # trava numa caixa de dialogo invisivel que nunca e respondida (ver comentario em
        # Open-WorkbookRobust) - o app parece simplesmente "congelar", sem nenhum erro pra
        # explicar o motivo.
        if ($c6Panel.Grid.Rows.Count -gt 0 -and -not $txtSenhaC6.Text) {
            [System.Windows.Forms.MessageBox]::Show("Informe a senha do C6 antes de analisar.", "Atencao") | Out-Null
            return
        }
        $mainForm.Cursor = "WaitCursor"
        $btnAnalisar.Enabled = $false
        $lblStatusArquivos.Text = "Lendo arquivos, aguarde..."
        # ProcessingLoader (components.md): substitui o conteudo da aba atual, centralizado,
        # enquanto o app le/bate as planilhas - a unica animacao continua do produto.
        $loader = New-DSProcessingLoader -Texto "Lendo arquivos"
        $tabArquivos.Controls.Add($loader)
        $loader.BringToFront()
        $mainForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $excel = $null
        try {
            $excel = New-ExcelApp
            $sistema = New-Object System.Collections.Generic.List[object]
            foreach ($row in $sisPanel.Grid.Rows) {
                $f = $row.Cells["ArquivoCompleto"].Value
                $un = $row.Cells["Unidade"].Value
                $recs = Read-SistemaFile -ExcelApp $excel -Path $f -Unidade $un
                foreach ($r in $recs) { $sistema.Add($r) | Out-Null }
            }
            $banco = New-Object System.Collections.Generic.List[object]
            foreach ($row in $c6Panel.Grid.Rows) {
                $f = $row.Cells["ArquivoCompleto"].Value
                $recs = Read-C6File -ExcelApp $excel -Path $f -Password $txtSenhaC6.Text
                foreach ($r in $recs) { $banco.Add($r) | Out-Null }
            }
            foreach ($row in $sicrediPanel.Grid.Rows) {
                $f = $row.Cells["ArquivoCompleto"].Value
                $recs = Read-SicrediFile -ExcelApp $excel -Path $f
                foreach ($r in $recs) { $banco.Add($r) | Out-Null }
            }

            $state.Sistema = $sistema
            $state.Banco = $banco

            $gridMapa.Rows.Clear()
            $terminais = $banco | Group-Object Banco, Terminal | Sort-Object { $_.Group[0].Banco }, Name
            foreach ($g in $terminais) {
                $bancoNome = $g.Group[0].Banco
                $terminal = $g.Group[0].Terminal
                $qtd = $g.Count
                $total = [Math]::Round((($g.Group | Where-Object { $_.Efetivada } | Measure-Object -Property Valor -Sum).Sum), 2)
                $sugestao = ""
                if ($bancoNome -eq "C6" -and $cfg.PdcUnidade.ContainsKey($terminal)) { $sugestao = $cfg.PdcUnidade[$terminal] }
                if ($bancoNome -eq "Sicredi" -and $cfg.EstabelecimentoUnidade.ContainsKey($terminal)) { $sugestao = $cfg.EstabelecimentoUnidade[$terminal] }
                $gridMapa.Rows.Add($bancoNome, $terminal, $qtd, $total, $sugestao) | Out-Null
            }

            $lblStatusArquivos.Text = "OK: $($sistema.Count) vendas do sistema, $($banco.Count) registros de banco lidos ($($terminais.Count) terminais/estabelecimentos encontrados). Va para a aba 'Mapeamento de unidade'."
            $btnGerar.Enabled = $true
            $tabs.SelectedTab = $tabMapa
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao ler arquivos: $($_.Exception.Message)", "Erro") | Out-Null
            $lblStatusArquivos.Text = "Erro: $($_.Exception.Message)"
        } finally {
            if ($excel) { Close-ExcelApp -ExcelApp $excel }
            $loader.Dispose()
            $mainForm.Cursor = "Default"
            $btnAnalisar.Enabled = $true
        }
    }.GetNewClosure())

    # ---------- ACAO: GERAR RELATORIO ----------
    $btnGerar.Add_Click({
        foreach ($row in $gridMapa.Rows) {
            if (-not $row.Cells["Unidade"].Value) {
                [System.Windows.Forms.MessageBox]::Show("Defina a unidade de todos os terminais/estabelecimentos na tabela.", "Atencao") | Out-Null
                return
            }
        }

        $pdcMap = @{}
        $estMap = @{}
        foreach ($row in $gridMapa.Rows) {
            $origem = $row.Cells["Origem"].Value
            $terminal = $row.Cells["Terminal"].Value
            $unidade = $row.Cells["Unidade"].Value
            if ($origem -eq "C6") { $pdcMap[$terminal] = $unidade } else { $estMap[$terminal] = $unidade }
        }
        Apply-UnitMapping -BancoRecords $state.Banco -PdcUnidade $pdcMap -EstabelecimentoUnidade $estMap
        $filtroUnidade = Remove-RegistrosForaDaRegraUnidade -SistemaRecords $state.Sistema -BancoRecords $state.Banco
        $state.Sistema = $filtroUnidade.Sistema
        $state.Banco = $filtroUnidade.Banco
        $senhasBancoSalvar = @{}
        if ($c6Panel.Grid.Rows.Count -gt 0) { $senhasBancoSalvar["C6"] = $txtSenhaC6.Text }
        Save-AppConfig -PdcUnidade $pdcMap -EstabelecimentoUnidade $estMap -SenhasBanco $senhasBancoSalvar

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "Excel (*.xlsx)|*.xlsx"
        $primeiroArquivo = $sisPanel.Grid.Rows[0].Cells["ArquivoCompleto"].Value
        $sfd.InitialDirectory = [System.IO.Path]::GetDirectoryName($primeiroArquivo)
        $sfd.FileName = "Conciliacao_" + (Get-Date).ToString("yyyy-MM-dd_HHmm") + ".xlsx"
        if ($sfd.ShowDialog() -ne "OK") { return }

        $mainForm.Cursor = "WaitCursor"
        $btnGerar.Enabled = $false
        $lblStatusMapa.Text = "Processando conciliacao, aguarde..."
        $loader = New-DSProcessingLoader -Texto "Gerando relatório"
        $tabMapa.Controls.Add($loader)
        $loader.BringToFront()
        $mainForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $excel = $null
        try {
            $resultado = Invoke-Reconciliacao -SistemaRecords $state.Sistema -BancoRecords $state.Banco
            $resumoFinal = Compute-ResumoFinal -SistemaRecords $state.Sistema -BancoRecords $state.Banco -Grupos $resultado.Grupos

            $excel = New-ExcelApp
            Export-RelatorioExcel -ExcelApp $excel -Resultado $resultado -Resumo $resumoFinal.Resumo -ResumoDiario $resumoFinal.ResumoDiario -SistemaRecords $state.Sistema -BancoRecords $state.Banco -OutputPath $sfd.FileName | Out-Null

            $totalDifAntes = [Math]::Round((($resumoFinal.Resumo | Measure-Object -Property SaldoOriginal -Sum).Sum), 2)
            $totalDifDepois = [Math]::Round((($resumoFinal.Resumo | Measure-Object -Property SaldoAjustado -Sum).Sum), 2)
            $valorSobraSistema = [Math]::Round((($resultado.SobrasSistema | Measure-Object -Property Valor -Sum).Sum), 2)
            $valorSobraBanco = [Math]::Round((($resultado.SobrasBanco | Measure-Object -Property Valor -Sum).Sum), 2)

            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine("RELATORIO SALVO EM: $($sfd.FileName)")
            if ($filtroUnidade.DescartadosSistema -gt 0 -or $filtroUnidade.DescartadosBanco -gt 0) {
                [void]$sb.AppendLine("Vila Moura concilia so Voucher: $($filtroUnidade.DescartadosSistema) registros de sistema e $($filtroUnidade.DescartadosBanco) registros de banco de outras formas foram descartados antes da conciliacao.")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Registros do sistema: $($state.Sistema.Count)")
            [void]$sb.AppendLine("Registros do banco efetivados (aprovados): $((($state.Banco | Where-Object {$_.Efetivada -and $_.Unidade -ne 'DESCONHECIDA'})).Count)")
            [void]$sb.AppendLine("Registros do banco recusados/devolvidos: $((($state.Banco | Where-Object {-not $_.Efetivada})).Count)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Grupos de correspondencia formados:")
            foreach ($g in ($resultado.Grupos | Group-Object Tipo | Sort-Object Count -Descending)) {
                [void]$sb.AppendLine("  - $($g.Name): $($g.Count)")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Sobras do sistema (sem correspondencia bancaria): $($resultado.SobrasSistema.Count) registros, R`$ $valorSobraSistema")
            [void]$sb.AppendLine("Sobras do banco (aprovacoes sem venda no sistema): $($resultado.SobrasBanco.Count) registros, R`$ $valorSobraBanco")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Diferenca total (Banco - Sistema) ANTES da reclassificacao: R`$ $totalDifAntes")
            [void]$sb.AppendLine("Diferenca total (Banco - Sistema) DEPOIS da reclassificacao: R`$ $totalDifDepois")
            if ($resultado.BancoDesconhecido.Count -gt 0) {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("ATENCAO: $($resultado.BancoDesconhecido.Count) registros de banco ficaram com unidade desconhecida.")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Consulte as abas do relatorio Excel para todos os detalhes, grupo a grupo, com rastreabilidade completa (arquivo e linha de origem).")

            $txtResultado.Text = $sb.ToString()
            $state.RelatorioPath = $sfd.FileName
            $btnAbrirRelatorio.Enabled = $true
            $tabs.SelectedTab = $tabResultado
            $lblStatusMapa.Text = "Relatorio gerado com sucesso."
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao gerar relatorio: $($_.Exception.Message)", "Erro") | Out-Null
            $lblStatusMapa.Text = "Erro: $($_.Exception.Message)"
        } finally {
            if ($excel) { Close-ExcelApp -ExcelApp $excel }
            $loader.Dispose()
            $mainForm.Cursor = "Default"
            $btnGerar.Enabled = $true
        }
    }.GetNewClosure())

    $btnAbrirRelatorio.Add_Click({
        if ($state.RelatorioPath -and (Test-Path $state.RelatorioPath)) {
            Start-Process $state.RelatorioPath
        }
    }.GetNewClosure())

    return $form
}

function New-FechamentoPanel {
    # Ver nota completa em New-ConciliacaoPanel: retorna um Panel (Dock=Fill) pra entrar no
    # content-root da janela unica do app, nao um Form proprio.
    $mainForm = $Script:MainForm
    $cfg = Load-FechamentoConfig

    $form = New-Object System.Windows.Forms.Panel
    $form.Dock = "Fill"
    $form.BackColor = $Script:DS.SurfacePage

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = "Fill"
    $tabs.Font = DSFont "button-label"
    $form.Controls.Add($tabs)
    Enable-ModuleTabsStyling -TabControl $tabs

    # O painel Dock=Top do botao "Voltar ao Hub" precisa ser adicionado DEPOIS do conteudo
    # Dock=Fill (ver nota em Add-BarraVoltarHub / licao registrada apos o bug dos botoes
    # sobrepostos na Conciliacao). Voltar entra antes do Topo (icone+titulo), na mesma ordem
    # usada em New-ConciliacaoPanel - assim o Topo fica mais externo/no topo da janela, com o
    # Voltar logo abaixo dele.
    Add-BarraVoltarHub -Form $form
    Add-DSTopo -Form $form -Titulo "Fechamento CP e DRE" | Out-Null

    # Texto das abas sem numero (o circulo numerado do ModuleTabs ja mostra a etapa).
    $tabArquivos = New-Object System.Windows.Forms.TabPage
    $tabArquivos.Text = "Arquivos"
    $tabArquivos.BackColor = $Script:DS.Surface
    $tabs.TabPages.Add($tabArquivos)

    $tabMapeamento = New-Object System.Windows.Forms.TabPage
    $tabMapeamento.Text = "Categorias"
    $tabMapeamento.BackColor = $Script:DS.Surface
    $tabs.TabPages.Add($tabMapeamento)

    $tabResultado = New-Object System.Windows.Forms.TabPage
    $tabResultado.Text = "Resultado"
    $tabResultado.BackColor = $Script:DS.Surface
    $tabs.TabPages.Add($tabResultado)

    # ---------- TAB 1: ARQUIVOS ----------
    $panelArquivos = New-Object System.Windows.Forms.Panel
    $panelArquivos.Dock = "Fill"
    $panelArquivos.BackColor = $Script:DS.Surface
    $panelArquivos.AutoScroll = $true
    $tabArquivos.Controls.Add($panelArquivos)

    # Painel intermediario de largura sincronizada a mao (ver nota identica em
    # New-ConciliacaoPanel): ancorar Right um filho DIRETO de um painel AutoScroll cria um loop
    # de realimentacao conhecido do WinForms. Os controles desta aba viram filhos deste painel
    # em vez de filhos diretos de $panelArquivos.
    $panelArquivosConteudo = New-Object System.Windows.Forms.Panel
    $panelArquivosConteudo.Location = New-Object System.Drawing.Point 0, 0
    $panelArquivosConteudo.Height = 330
    # Largura inicial FIXA (950), nao lida de $panelArquivos.ClientSize.Width nesse ponto da
    # construcao (ainda cai no piso de 700, antes do Form passar pelo layout de verdade) - ver
    # nota completa em New-ConciliacaoPanel, mesmo bug: os filhos (New-SingleFilePicker, mais
    # abaixo) calculam sua posicao a partir de $Parent.Width NA HORA em que sao criados, entao
    # precisam de um valor ja correto (compativel com o design original de 920/930px) pra nao
    # ancorar com uma folga errada que so quebra visivelmente depois, numa janela bem larga.
    $panelArquivosConteudo.Width = 950
    $panelArquivosConteudo.BackColor = $Script:DS.Surface
    $panelArquivos.Controls.Add($panelArquivosConteudo)
    $panelArquivos.Add_Resize({
        param($s, $e)
        $panelArquivosConteudo.Width = [Math]::Max($s.ClientSize.Width, 700)
    }.GetNewClosure())

    $panelArquivosBottom = New-Object System.Windows.Forms.Panel
    $panelArquivosBottom.Dock = "Bottom"
    $panelArquivosBottom.Height = 60
    $panelArquivosBottom.BackColor = $Script:DS.Surface
    $tabArquivos.Controls.Add($panelArquivosBottom)

    # Espacamento generoso de proposito (ver nota identica em New-ConciliacaoPanel): usuario
    # reportou os textos/controles muito colados em todas as abas.
    # Toda a geometria desta aba deriva da altura/largura REAIS das fontes (GetPreferredSize,
    # Height, MeasureText) em vez de pixels fixos: o app e DPI-aware e o Windows em 125%/150%
    # aumenta as fontes (em pontos) mas nao os numeros fixos do layout - com posicoes fixas os
    # radio buttons se sobrepunham, o grupo ficava baixo demais, os rotulos encostavam nas
    # caixas e o texto explicativo virava uma linha so cortada na borda da janela.
    $grpModo = New-Object System.Windows.Forms.GroupBox
    $grpModo.Text = "Modo de fechamento"
    $grpModo.Font = DSFont "body"
    $grpModo.Location = New-Object System.Drawing.Point($Script:DSSpace4, $Script:DSSpace4)
    $grpModo.Anchor = "Top,Left"
    $panelArquivosConteudo.Controls.Add($grpModo)

    $rbVencimento = New-Object System.Windows.Forms.RadioButton
    $rbVencimento.Text = "Por Vencimento"
    $rbVencimento.Font = DSFont "body"
    $rbVencimento.AutoSize = $true
    $rbVencimento.Checked = $true
    $rbVencimento.Size = $rbVencimento.GetPreferredSize((New-Object System.Drawing.Size 0, 0))
    # Filhos de GroupBox tem coordenadas a partir do topo da CAIXA (nao da area util), entao o Y
    # tem que comecar abaixo da faixa do titulo (DisplayRectangle.Top), senao o radio cobre o
    # titulo "Modo de fechamento".
    $yRadios = $grpModo.DisplayRectangle.Top + $Script:DSSpace1
    $rbVencimento.Location = New-Object System.Drawing.Point($Script:DSSpace4, $yRadios)
    $grpModo.Controls.Add($rbVencimento)

    $rbCompetencia = New-Object System.Windows.Forms.RadioButton
    $rbCompetencia.Text = "Por Competência"
    $rbCompetencia.Font = DSFont "body"
    $rbCompetencia.AutoSize = $true
    $rbCompetencia.Size = $rbCompetencia.GetPreferredSize((New-Object System.Drawing.Size 0, 0))
    $rbCompetencia.Location = New-Object System.Drawing.Point(($rbVencimento.Right + $Script:DSSpace6), $yRadios)
    $grpModo.Controls.Add($rbCompetencia)

    # Grupo dimensionado pelos radios: largura = ate o fim do 2o radio + margem; altura = ate o
    # fim dos radios + folga.
    $grpModo.Size = New-Object System.Drawing.Size(($rbCompetencia.Right + $Script:DSSpace4), ($yRadios + $rbCompetencia.Height + $Script:DSSpace3))

    # AutoSize=$true (padrao do Label) ignora o Size e deixa o texto em UMA linha so, que passa
    # da borda da janela - desligado, o texto quebra dentro da largura. Altura reservada pro
    # pior caso: o maior dos dois textos quebrado na menor largura possivel do painel (700).
    $textoVencimento = "Modo VENCIMENTO: despesa = titulos pela data de vencimento no periodo; receita = extrato dos bancos relacionados (C6/Sicredi)."
    $textoCompetencia = "Modo COMPETÊNCIA: despesa = lançamentos de gastos emitidos no periodo; receita = faturamento do sistema no periodo."
    $fonteExplicacao = DSFont "caption"
    $larguraMinExplicacao = 700 - (2 * $Script:DSSpace4)
    $alturaExplicacao = 0
    foreach ($t in @($textoVencimento, $textoCompetencia)) {
        $h = [System.Windows.Forms.TextRenderer]::MeasureText($t, $fonteExplicacao, (New-Object System.Drawing.Size($larguraMinExplicacao, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height
        if ($h -gt $alturaExplicacao) { $alturaExplicacao = $h }
    }
    $lblExplicacao = New-Object System.Windows.Forms.Label
    $lblExplicacao.Font = $fonteExplicacao
    $lblExplicacao.ForeColor = $Script:DS.InkMuted
    $lblExplicacao.AutoSize = $false
    $lblExplicacao.Location = New-Object System.Drawing.Point($Script:DSSpace4, ($grpModo.Bottom + $Script:DSSpace4))
    $lblExplicacao.Size = New-Object System.Drawing.Size(($panelArquivosConteudo.Width - (2 * $Script:DSSpace4)), ($alturaExplicacao + $Script:DSSpace1))
    $lblExplicacao.Anchor = "Top,Left,Right"
    $panelArquivosConteudo.Controls.Add($lblExplicacao)

    function New-SingleFilePicker {
        param($Parent, [string]$Label, [int]$Top)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Label
        $lbl.Font = DSFont "body"
        $lbl.ForeColor = $Script:DS.Ink
        $lbl.Location = New-Object System.Drawing.Point($Script:DSSpace4, $Top)
        $lbl.AutoSize = $true
        $Parent.Controls.Add($lbl)

        # Caixa logo abaixo do rotulo (pela altura REAL dele, nao um deslocamento fixo) e botao
        # com a mesma altura e mesmo Y da caixa - margens iguais (space-4) dos dois lados.
        $larguraBotao = 150
        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point($Script:DSSpace4, ($lbl.Bottom + $Script:DSSpace1))
        $txt.Width = ($Parent.Width - (3 * $Script:DSSpace4) - $larguraBotao)
        $txt.Anchor = "Top,Left,Right"
        $txt.Font = DSFont "body"
        $txt.ReadOnly = $true
        $txt.AllowDrop = $true
        $Parent.Controls.Add($txt)

        $btn = New-DSBotaoSecundario -Texto "Selecionar..."
        $btn.Size = New-Object System.Drawing.Size($larguraBotao, $txt.Height)
        $btn.Location = New-Object System.Drawing.Point(($Parent.Width - $Script:DSSpace4 - $larguraBotao), $txt.Top)
        $btn.Anchor = "Top,Right"
        $Parent.Controls.Add($btn)

        $picker = [PSCustomObject]@{ Label = $lbl; TextBox = $txt; Button = $btn; Path = "" }
        $txt.Add_DragEnter({
            param($s, $e)
            if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy }
            else { $e.Effect = [System.Windows.Forms.DragDropEffects]::None }
        })
        $txt.Add_DragDrop({
            param($s, $e)
            $paths = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
            if ($paths -and $paths.Count -gt 0 -and (Test-Path $paths[0] -PathType Leaf)) {
                $picker.Path = $paths[0]; $picker.TextBox.Text = $paths[0]
            }
        }.GetNewClosure())
        return $picker
    }

    $despesaPicker = New-SingleFilePicker -Parent $panelArquivosConteudo -Label "Planilha de despesas (Contas a Pagar):" -Top ($lblExplicacao.Bottom + $Script:DSSpace6)
    $receitaPicker = New-SingleFilePicker -Parent $panelArquivosConteudo -Label "Planilha de receita:" -Top ($despesaPicker.TextBox.Bottom + $Script:DSSpace6)
    $panelArquivosConteudo.Height = $receitaPicker.TextBox.Bottom + $Script:DSSpace6

    $atualizaTextoModo = {
        if ($rbVencimento.Checked) { $lblExplicacao.Text = $textoVencimento } else { $lblExplicacao.Text = $textoCompetencia }
    }.GetNewClosure()
    & $atualizaTextoModo
    $rbVencimento.Add_CheckedChanged($atualizaTextoModo)
    $rbCompetencia.Add_CheckedChanged($atualizaTextoModo)

    $ofdFechamento = New-Object System.Windows.Forms.OpenFileDialog
    $ofdFechamento.Filter = "Excel (*.xlsx;*.xls)|*.xlsx;*.xls|Todos os arquivos (*.*)|*.*"

    $despesaPicker.Button.Add_Click({
        $ofdFechamento.Title = "Selecionar planilha de despesas"
        if ($ofdFechamento.ShowDialog($mainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $despesaPicker.Path = $ofdFechamento.FileName
            $despesaPicker.TextBox.Text = $ofdFechamento.FileName
        }
    }.GetNewClosure())

    $receitaPicker.Button.Add_Click({
        $ofdFechamento.Title = "Selecionar planilha de receita"
        if ($ofdFechamento.ShowDialog($mainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $receitaPicker.Path = $ofdFechamento.FileName
            $receitaPicker.TextBox.Text = $ofdFechamento.FileName
        }
    }.GetNewClosure())

    $btnGerar = New-DSBotao -Texto "Gerar Fechamento >>" -Variante "primary"
    $btnGerar.Location = New-Object System.Drawing.Point($Script:DSSpace4, 12)
    $btnGerar.Size = New-Object System.Drawing.Size(250, 36)
    $panelArquivosBottom.Controls.Add($btnGerar)

    $lblStatusArquivos = New-Object System.Windows.Forms.Label
    $lblStatusArquivos.Font = DSFont "caption"
    $lblStatusArquivos.ForeColor = $Script:DS.InkMuted
    $lblStatusArquivos.Location = New-Object System.Drawing.Point(($Script:DSSpace4 + 250 + $Script:DSSpace6), 5)
    $lblStatusArquivos.Size = New-Object System.Drawing.Size(750, 50)
    $lblStatusArquivos.Anchor = "Top,Left,Right,Bottom"
    $panelArquivosBottom.Controls.Add($lblStatusArquivos)

    # ---------- TAB 2: MAPEAMENTO DE CATEGORIAS ----------
    $gridMapa = New-Object System.Windows.Forms.DataGridView
    $gridMapa.Dock = "Fill"
    Set-DSGridStyle -Grid $gridMapa
    $gridMapa.AllowUserToAddRows = $true
    $gridMapa.AllowUserToDeleteRows = $true
    $gridMapa.RowHeadersVisible = $false
    $tabMapeamento.Controls.Add($gridMapa)

    $panelMapaBottom = New-Object System.Windows.Forms.Panel
    $panelMapaBottom.Dock = "Bottom"
    $panelMapaBottom.Height = 50
    $panelMapaBottom.BackColor = $Script:DS.Surface
    $tabMapeamento.Controls.Add($panelMapaBottom)

    $colDescricao = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colDescricao.Name = "Descricao"; $colDescricao.HeaderText = "Descrição C. Gerencial"
    $colDescricao.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $gridMapa.Columns.Add($colDescricao) | Out-Null
    $colMacro = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMacro.Name = "Macro"; $colMacro.HeaderText = "Macro DRE"
    $colMacro.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $gridMapa.Columns.Add($colMacro) | Out-Null

    foreach ($k in ($cfg.MapaMacroDRE.Keys | Sort-Object)) { $gridMapa.Rows.Add($k, $cfg.MapaMacroDRE[$k]) | Out-Null }

    $btnSalvarMapa = New-DSBotao -Texto "Salvar mapeamento" -Variante "primary"
    $btnSalvarMapa.Location = New-Object System.Drawing.Point($Script:DSSpace4, 8)
    $btnSalvarMapa.Size = New-Object System.Drawing.Size(160, 34)
    $panelMapaBottom.Controls.Add($btnSalvarMapa)

    $btnRestaurarMapa = New-DSBotaoSecundario -Texto "Restaurar padrão"
    $btnRestaurarMapa.Location = New-Object System.Drawing.Point(($Script:DSSpace4 + 160 + $Script:DSSpace4), 8)
    $btnRestaurarMapa.Size = New-Object System.Drawing.Size(140, 34)
    $panelMapaBottom.Controls.Add($btnRestaurarMapa)

    $lblStatusMapa = New-Object System.Windows.Forms.Label
    $lblStatusMapa.Font = DSFont "caption"
    $lblStatusMapa.ForeColor = $Script:DS.InkMuted
    $lblStatusMapa.Location = New-Object System.Drawing.Point(($Script:DSSpace4 + 160 + $Script:DSSpace4 + 140 + $Script:DSSpace6), 12)
    $lblStatusMapa.Size = New-Object System.Drawing.Size(600, 30)
    $panelMapaBottom.Controls.Add($lblStatusMapa)

    $btnSalvarMapa.Add_Click({
        $mapa = @{}
        foreach ($row in $gridMapa.Rows) {
            $d = "$($row.Cells['Descricao'].Value)".Trim()
            $m = "$($row.Cells['Macro'].Value)".Trim()
            if ($d -ne "" -and $m -ne "") { $mapa[$d.ToUpperInvariant()] = $m.ToUpperInvariant() }
        }
        Save-FechamentoConfig -MapaMacroDRE $mapa
        $lblStatusMapa.Text = "Mapeamento salvo ($($mapa.Count) categorias)."
    }.GetNewClosure())

    # Copia local pro closure capturar por valor via GetNewClosure(): ver nota em
    # Enable-ModuleTabsStyling sobre $Script:X direto num event handler assincrono.
    $mapaMacroDREPadrao = $Script:MapaMacroDREPadrao
    $btnRestaurarMapa.Add_Click({
        $gridMapa.Rows.Clear()
        foreach ($k in ($mapaMacroDREPadrao.Keys | Sort-Object)) { $gridMapa.Rows.Add($k, $mapaMacroDREPadrao[$k]) | Out-Null }
        $lblStatusMapa.Text = "Mapeamento padrão restaurado (clique em Salvar para confirmar)."
    }.GetNewClosure())

    # ---------- TAB 3: RESULTADO ----------
    $txtResultado = New-Object System.Windows.Forms.TextBox
    $txtResultado.Multiline = $true
    $txtResultado.ReadOnly = $true
    $txtResultado.ScrollBars = "Vertical"
    $txtResultado.Dock = "Fill"
    $txtResultado.BackColor = $Script:DS.Surface
    $txtResultado.ForeColor = $Script:DS.Ink
    $txtResultado.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tabResultado.Controls.Add($txtResultado)

    $panelResultadoBottom = New-Object System.Windows.Forms.Panel
    $panelResultadoBottom.Dock = "Bottom"
    $panelResultadoBottom.Height = 50
    $panelResultadoBottom.BackColor = $Script:DS.Surface
    $tabResultado.Controls.Add($panelResultadoBottom)

    $btnAbrirRelatorio = New-DSBotao -Texto "Abrir relatório Excel" -Variante "primary"
    $btnAbrirRelatorio.Location = New-Object System.Drawing.Point($Script:DSSpace4, 8)
    $btnAbrirRelatorio.Size = New-Object System.Drawing.Size(180, 34)
    $btnAbrirRelatorio.Enabled = $false
    $panelResultadoBottom.Controls.Add($btnAbrirRelatorio)

    # ---------- ACAO: GERAR FECHAMENTO ----------
    $state = [PSCustomObject]@{ RelatorioPath = $null }

    $btnGerar.Add_Click({
        if (-not $despesaPicker.Path) {
            [System.Windows.Forms.MessageBox]::Show("Selecione a planilha de despesas.", "Atenção") | Out-Null
            return
        }
        if (-not $receitaPicker.Path) {
            [System.Windows.Forms.MessageBox]::Show("Selecione a planilha de receita.", "Atenção") | Out-Null
            return
        }

        $modo = if ($rbVencimento.Checked) { "Vencimento" } else { "Competencia" }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "Excel (*.xlsx)|*.xlsx"
        $sfd.FileName = "Fechamento_${modo}_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
        if ($sfd.ShowDialog($mainForm) -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $btnGerar.Enabled = $false
        $mainForm.Cursor = "WaitCursor"
        $lblStatusArquivos.Text = "Lendo arquivos..."
        $loader = New-DSProcessingLoader -Texto "Lendo arquivos"
        $tabArquivos.Controls.Add($loader)
        $loader.BringToFront()
        $mainForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $excel = $null
        try {
            $excel = New-ExcelApp

            $mapaAtual = @{}
            foreach ($row in $gridMapa.Rows) {
                $d = "$($row.Cells['Descricao'].Value)".Trim()
                $m = "$($row.Cells['Macro'].Value)".Trim()
                if ($d -ne "" -and $m -ne "") { $mapaAtual[$d.ToUpperInvariant()] = $m.ToUpperInvariant() }
            }

            $despesaRecords = Read-DespesaFile -ExcelApp $excel -Path $despesaPicker.Path -Modo $modo -MapaMacroDRE $mapaAtual
            if ($despesaRecords.Count -eq 0) { throw "Nenhum registro de despesa encontrado (confira o modo selecionado e a coluna de data correspondente)." }

            $receitaRecords = Read-ReceitaFile -ExcelApp $excel -Path $receitaPicker.Path

            $resultado = Compute-Fechamento -DespesaRecords $despesaRecords -ReceitaRecords $receitaRecords

            if (Test-Path $sfd.FileName) { Remove-Item $sfd.FileName -Force }
            Export-RelatorioFechamento -ExcelApp $excel -Resultado $resultado -DespesaRecords $despesaRecords -ReceitaRecords $receitaRecords -MapaMacroDRE $mapaAtual -OutputPath $sfd.FileName | Out-Null

            $dreCons = $resultado.DrePorUnidade["CONSOLIDADO"]
            $naoMapeados = @($despesaRecords | Where-Object { $_.MacroDRE -eq "NÃO MAPEADO" })

            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine("RELATORIO SALVO EM: $($sfd.FileName)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Modo: $modo")
            [void]$sb.AppendLine("Período: $($resultado.Periodo)")
            [void]$sb.AppendLine("Unidades: $($resultado.Unidades -join ', ')")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Faturamento bruto: R`$ $($dreCons.FaturamentoBruto)")
            [void]$sb.AppendLine("CMV: R`$ $($dreCons.CMV)")
            [void]$sb.AppendLine("EBITDA: R`$ $($dreCons.EBITDA)")
            [void]$sb.AppendLine("Resultado geral: R`$ $($dreCons.ResultadoGeral)")
            [void]$sb.AppendLine("")
            if ($naoMapeados.Count -gt 0) {
                [void]$sb.AppendLine("ATENÇÃO: $($naoMapeados.Count) lançamentos com categoria não mapeada (aba Premissas e Checks / aba 2 do app).")
            }
            if ($dreCons.FaturamentoBruto -le 0) {
                [void]$sb.AppendLine("ATENÇÃO: receita total zerada - confira a planilha de receita selecionada.")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Consulte as abas do relatório Excel para o detalhamento por categoria e unidade.")

            $txtResultado.Text = $sb.ToString()
            $state.RelatorioPath = $sfd.FileName
            $btnAbrirRelatorio.Enabled = $true
            $tabs.SelectedTab = $tabResultado
            $lblStatusArquivos.Text = "Fechamento gerado com sucesso."
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao gerar fechamento: $($_.Exception.Message)", "Erro") | Out-Null
            $lblStatusArquivos.Text = "Erro: $($_.Exception.Message)"
        } finally {
            if ($excel) { Close-ExcelApp -ExcelApp $excel }
            $loader.Dispose()
            $mainForm.Cursor = "Default"
            $btnGerar.Enabled = $true
        }
    }.GetNewClosure())

    $btnAbrirRelatorio.Add_Click({
        if ($state.RelatorioPath -and (Test-Path $state.RelatorioPath)) { Start-Process $state.RelatorioPath }
    }.GetNewClosure())

    return $form
}

function New-CardGridPanel {
    # Tela generica de "cards" (padrao ModuleCard do design system): usada tanto pela Home
    # (Concilia) quanto pela tela de Relatorios. Cada modulo precisa de
    # Titulo/Descricao/Habilitado/Acao (scriptblock que retorna um Panel, via Navigate-Forward)
    # e BotaoTexto (texto do pill quando desabilitado, ex.: "Em breve" ou "Em manutenção";
    # habilitados sempre mostram "Abrir").
    # -ComBotaoVoltar adiciona o link "Voltar" no topo (telas abertas a partir de outra tela);
    # a tela raiz (Home) nao usa, pois nao ha pra onde voltar - e tambem decide a tipografia
    # do titulo (title-app so na Home, title-module nas demais).
    # Retorna um Panel (Dock=Fill) pro content-root da janela unica do app (ver
    # Navigate-Forward/Navigate-Back em Start-App) - nao e mais um Form proprio, entao o
    # tamanho da janela nao depende mais da quantidade de cards; so o layout INTERNO deles usa
    # $cardWidth/$cardHeight.
    param([string]$Titulo, [string]$Subtitulo, [array]$Modulos, [switch]$ComBotaoVoltar)

    $cardWidth = 456
    $cardHeight = 108
    $chipTamanho = 40

    $form = New-Object System.Windows.Forms.Panel
    $form.Dock = "Fill"
    $form.BackColor = $Script:DS.SurfacePage
    # SuspendLayout enquanto monta os 3 paineis Dock (Fill + ate 2x Top): sem isso, o WinForms
    # pode rodar uma passada de layout com um conjunto PARCIAL de filhos dock (ex.: so o Fill,
    # antes do Topo/Voltar serem adicionados) e o painel AutoScroll calcula/cacheia a area
    # errada - foi exatamente o bug visto na tela Relatorios (cards nascendo por cima do
    # topo/regua verde, so quando ha os 3 paineis Dock ao mesmo tempo).
    $form.SuspendLayout()

    # Painel Dock=Fill com AutoScroll pros cards, adicionado ANTES do Topo/Voltar (Dock=Top) -
    # mesma ordem ja validada em New-ConciliacaoPanel/New-FechamentoPanel (Fill primeiro, Top
    # depois: o WinForms doca na ordem inversa a que os controles sao adicionados, entao o
    # ultimo Top adicionado reserva sua faixa primeiro; se o Fill fosse adicionado depois de um
    # Top, o Fill preencheria a janela inteira por cima dele). Os cards vivem dentro de
    # $colunaCards (abaixo), que e recentralizada inteira no Add_Resize, ja que os cards tem largura fixa
    # por design (nao esticam como grade/formulario) - so a posicao X muda, nunca a largura.
    $panelCards = New-Object System.Windows.Forms.Panel
    $panelCards.Dock = "Fill"
    $panelCards.BackColor = $Script:DS.SurfacePage
    $panelCards.AutoScroll = $true
    $form.Controls.Add($panelCards)

    # Coluna interna de largura fixa (a mesma tecnica de panelArquivosConteudo em
    # New-ConciliacaoPanel) que junta todos os cards - so ELA e recentralizada no Add_Resize,
    # nunca os cards individualmente. Reposicionar N controles um por um no mesmo evento e
    # fragil (um deles pode nao pegar a posicao certa se o Resize disparar de novo no meio do
    # loop, ex.: AutoScroll recalculando a barra de rolagem); mover 1 unico container e atomico.
    $colunaCards = New-Object System.Windows.Forms.Panel
    $colunaCards.Location = New-Object System.Drawing.Point $Script:DSSpace8, 0
    $colunaCards.Width = $cardWidth
    $colunaCards.Height = $Script:DSSpace6 + ($Modulos.Count * ($cardHeight + $Script:DSSpace6))
    $colunaCards.BackColor = $Script:DS.SurfacePage
    $panelCards.Controls.Add($colunaCards)
    # $margemMinima local: $Script:DSSpace8 referenciado direto dentro do Add_Resize (evento
    # assincrono) voltava nulo no exe compilado - mesmo bug ja visto em Enable-ModuleTabsStyling.
    $margemMinima = $Script:DSSpace8
    $panelCards.Add_Resize({
        param($s, $e)
        $colunaCards.Location = New-Object System.Drawing.Point ([Math]::Max($margemMinima, [Math]::Round(($s.ClientSize.Width - $cardWidth) / 2))), 0
    }.GetNewClosure())

    # Add-BarraVoltarHub adicionado ANTES de Add-DSTopo de proposito (ver nota de Dock=Top
    # em ambas): o ultimo Dock=Top adicionado fica mais externo, entao o Topo (adicionado
    # depois, logo abaixo) fica no topo da janela, com o Voltar logo abaixo do titulo.
    if ($ComBotaoVoltar) { Add-BarraVoltarHub -Form $form }

    Add-DSTopo -Form $form -Titulo $Titulo -FonteTitulo $(if ($ComBotaoVoltar) { "title-module" } else { "title-app" }) -Subtitulo $Subtitulo | Out-Null

    $top = $Script:DSSpace6
    foreach ($mod in $Modulos) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(0, $top)
        $card.Size = New-Object System.Drawing.Size($cardWidth, $cardHeight)
        $card.BackColor = $Script:DS.Surface
        $colunaCards.Controls.Add($card)
        # Sem Region-clip de proposito (ver nota em New-DSBotao): a Region do GDI nao tem
        # antialiasing, entao o corte arredondado sairia serrilhado. A borda abaixo ja e
        # desenhada com AntiAlias, e a diferenca entre Surface (branco) do card e SurfacePage
        # (quase branco) do fundo da tela e minima demais pra notar na fatia de canto que sobra.
        Set-DSCardVisual -Card $card -Raio $Script:DSRadiusLg

        $chip = New-DSIconeModulo -Habilitado $mod.Habilitado -Tamanho $chipTamanho
        $chip.Location = New-Object System.Drawing.Point $Script:DSSpace4, ([Math]::Round(($cardHeight - $chipTamanho) / 2))
        $card.Controls.Add($chip)
        $xTexto = $Script:DSSpace4 + $chipTamanho + $Script:DSSpace3

        $lblModTitulo = New-Object System.Windows.Forms.Label
        $lblModTitulo.Text = $mod.Titulo
        $lblModTitulo.Font = DSFont "body-strong"
        $lblModTitulo.ForeColor = if ($mod.Habilitado) { $Script:DS.Ink } else { $Script:DS.InkMuted }
        $lblModTitulo.AutoSize = $true
        $lblModTitulo.Location = New-Object System.Drawing.Point $xTexto, $Script:DSSpace3
        $card.Controls.Add($lblModTitulo)

        $lblModDesc = New-Object System.Windows.Forms.Label
        $lblModDesc.Text = $mod.Descricao
        $lblModDesc.Font = DSFont "caption"
        $lblModDesc.ForeColor = $Script:DS.InkMuted
        # AutoSize=true deixava a descricao crescer pra direita sem limite, invadindo o botao
        # quando o texto era mais longo. Com AutoSize=false e um tamanho fixo, o Label quebra
        # linha sozinho dentro da largura definida.
        $lblModDesc.AutoSize = $false
        $lblModDesc.Location = New-Object System.Drawing.Point $xTexto, ($Script:DSSpace3 + 22 + $Script:DSSpace2)
        $lblModDesc.Size = New-Object System.Drawing.Size(($cardWidth - $xTexto - 140), 54)
        $card.Controls.Add($lblModDesc)

        $btnAbrir = New-DSBotao -Texto $(if ($mod.Habilitado) { "Abrir" } else { $mod.BotaoTexto }) -Variante $(if ($mod.Habilitado) { "primary" } else { "disabled" })
        $btnAbrir.Size = New-Object System.Drawing.Size(104, 36)
        $btnAbrir.Location = New-Object System.Drawing.Point(($cardWidth - 104 - $Script:DSSpace4), (($cardHeight - 36) / 2))
        $card.Controls.Add($btnAbrir)

        if ($mod.Habilitado) {
            $btnAbrir.Add_Click({
                Navigate-Forward -PanelBuilder $mod.Acao -Titulo $mod.Titulo
            }.GetNewClosure())
        }

        $top += $cardHeight + $Script:DSSpace6
    }

    $form.ResumeLayout($true)
    return $form
}

# Modulos da tela "Relatorios" (a antiga tela unica do Hub). So Conciliacao de Vendas e
# Fechamento CP e DRE estao implementados; os demais ficam desabilitados ("Em breve") e sao
# ativados aos poucos, sem precisar mexer na estrutura da tela em si.
$Script:ModulosRelatorios = @(
    [PSCustomObject]@{ Titulo = "Conciliacao de Vendas"; Descricao = "Compara vendas do sistema (Mooca / Vila Moura) com C6 e Sicredi"; Habilitado = $true; BotaoTexto = "Abrir"; Acao = { New-ConciliacaoPanel } }
    [PSCustomObject]@{ Titulo = "Fechamento CP e DRE"; Descricao = "Fecha contas a pagar e monta a DRE gerencial, por vencimento ou por competência"; Habilitado = $true; BotaoTexto = "Abrir"; Acao = { New-FechamentoPanel } }
    [PSCustomObject]@{ Titulo = "Fluxo de Caixa"; Descricao = "Em breve"; Habilitado = $false; BotaoTexto = "Em breve"; Acao = $null }
    [PSCustomObject]@{ Titulo = "Contas a Receber"; Descricao = "Em breve"; Habilitado = $false; BotaoTexto = "Em breve"; Acao = $null }
    [PSCustomObject]@{ Titulo = "Indicadores Financeiros"; Descricao = "Em breve"; Habilitado = $false; BotaoTexto = "Em breve"; Acao = $null }
)

function New-HomePanel {
    # Tela inicial do app (Concilia): duas opcoes - Movimentacoes (em manutencao, sera
    # desenvolvida depois) e Relatorios (abre a tela com os modulos financeiros existentes).
    # Construida uma unica vez, dentro de Start-App - nunca reconstruida/descartada durante a
    # navegacao (fica parada no fundo do $Script:TelaStack, ver Navigate-Forward/Navigate-Back),
    # igual a Home ja se comportava antes de existir uma janela unica (o Form dela persistia
    # a execucao toda; agora quem persiste e $Script:MainForm, e este Panel simplesmente nunca
    # e removido da pilha).
    $mainForm = $Script:MainForm
    $modulosHome = @(
        [PSCustomObject]@{ Titulo = "Movimentações"; Descricao = "Em manutenção - em desenvolvimento"; Habilitado = $false; BotaoTexto = "Em manutenção"; Acao = $null }
        [PSCustomObject]@{ Titulo = "Relatórios"; Descricao = "Conciliação de vendas, fechamento e outros relatórios financeiros"; Habilitado = $true; BotaoTexto = "Abrir"; Acao = { New-CardGridPanel -Titulo "Relatórios" -Subtitulo "Escolha o modulo que deseja utilizar:" -Modulos $Script:ModulosRelatorios -ComBotaoVoltar } }
    )
    $homeForm = New-CardGridPanel -Titulo "Concilia" -Subtitulo "Escolha o que deseja fazer:" -Modulos $modulosHome

    $lblVersao = New-Object System.Windows.Forms.Label
    $lblVersao.Text = "v$Script:AppVersion"
    $lblVersao.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblVersao.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $lblVersao.AutoSize = $true
    $homeForm.Controls.Add($lblVersao)
    # BringToFront: $panelCards (Dock=Fill, dentro de New-CardGridPanel) cobre a tela inteira
    # e foi adicionado ANTES deste label - sem isso o label fica escondido atras do painel
    # opaco dos cards (bug real: sumiu da tela depois que os cards viraram Dock=Fill).
    $lblVersao.BringToFront()

    # Link "Verificar atualizações" - checagem manual, pro usuario nao precisar esperar o
    # Timer periodico (30 min, mais abaixo) quando quiser conferir na hora.
    $lblVerificar = New-Object System.Windows.Forms.Label
    $lblVerificar.Text = "Verificar atualizações"
    $lblVerificar.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblVerificar.ForeColor = $Script:DS.Brand600
    $lblVerificar.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblVerificar.AutoSize = $true
    $homeForm.Controls.Add($lblVerificar)
    $lblVerificar.BringToFront()

    # Checagem de atualizacao roda uma vez por sessao do app (Get-AtualizacaoInfoCache
    # memoiza), disparada aqui na Home. Se houver versao mais nova, pergunta antes de baixar e
    # instalar; se nao houver internet ou o repositorio estiver fora do ar, ignora
    # silenciosamente (ver Test-AtualizacaoDisponivel). Alem do dialogo inicial, um link
    # persistente (New-DSLinkAtualizacao) fica visivel aqui e em toda tela aberta depois (ver
    # Add-BarraVoltarHub) pra avisar o usuario mesmo se ele fechar o dialogo com Nao ou so vir a
    # ver o aviso depois de ja estar no meio de um modulo.
    # Copia local pro closure capturar por valor via GetNewClosure(): $Script:AppVersion direto
    # dentro de um event handler assincrono (dispara pelo message loop do WinForms, nao na
    # hora) voltava nulo no exe compilado - mesmo bug ja visto em Enable-ModuleTabsStyling.
    $versaoAtual = $Script:AppVersion
    $urlInstalador = $Script:UpdateInstallerUrl
    # Estado mutavel compartilhado entre o aviso inicial (Add_Shown), a checagem periodica
    # (Timer) e a checagem manual (link acima) pra nao repetir o popup/link da mesma versao -
    # PSCustomObject em vez de variavel escalar simples porque cada GetNewClosure() captura
    # por valor; os tres closures guardam a MESMA instancia, entao a mutacao feita num aparece
    # pros outros (mesmo padrao de $relogio/$visitadas ja usado no arquivo).
    # Link = referencia ao label "Nova versao disponivel" depois de criado (null ate la), pra
    # o reposicionamento no Resize (abaixo) conseguir move-lo tambem, nao so no momento em que
    # foi criado - a Home agora e redimensionavel, entao a posicao no canto inferior direito
    # precisa ser recalculada toda vez que o tamanho da janela muda, nao so uma vez.
    $estadoNotificacao = [PSCustomObject]@{ UltimaVersaoAvisada = $null; LinkAdicionado = $false; Link = $null }

    # Reposiciona o rodape (versao + Verificar atualizacoes + o link de update se existir) no
    # canto inferior direito - chamado tanto no Add_Shown quanto em todo Add_Resize depois,
    # pra continuar no lugar certo conforme a janela e redimensionada.
    # BringToFront chamado de novo a cada reposicionamento (nao so uma vez na criacao): o
    # painel Dock=Fill dos cards ($panelCards) parece reafirmar seu proprio z-order a cada
    # passada de layout do WinForms (ex.: durante um Resize), entao um BringToFront feito so
    # na hora de criar o label nao sobrevive a um segundo redimensionamento - o rodape sumia de
    # novo depois de mexer no tamanho da janela uma segunda vez.
    $posicionarRodape = {
        $lblVersao.Location = New-Object System.Drawing.Point(($homeForm.ClientSize.Width - $lblVersao.Width - 12), ($homeForm.ClientSize.Height - $lblVersao.Height - 8))
        $lblVersao.BringToFront()
        $lblVerificar.Location = New-Object System.Drawing.Point(($lblVersao.Location.X - $lblVerificar.Width - 10), ($homeForm.ClientSize.Height - $lblVerificar.Height - 8))
        $lblVerificar.BringToFront()
        if ($estadoNotificacao.Link) {
            $estadoNotificacao.Link.Location = New-Object System.Drawing.Point(($homeForm.ClientSize.Width - $estadoNotificacao.Link.Width - 12), ($homeForm.ClientSize.Height - $lblVersao.Height - $estadoNotificacao.Link.Height - 12))
            $estadoNotificacao.Link.BringToFront()
        }
    }.GetNewClosure()

    # Logica compartilhada pelos tres gatilhos (abertura, Timer, botao manual) de "achou uma
    # atualizacao": adiciona o link persistente (uma vez so) e mostra o popup de confirmacao.
    $tratarAtualizacaoEncontrada = {
        param($Upd)
        $estadoNotificacao.UltimaVersaoAvisada = $Upd.Versao
        if (-not $estadoNotificacao.LinkAdicionado) {
            $estadoNotificacao.LinkAdicionado = $true
            $lblUpd = New-DSLinkAtualizacao -Upd $Upd
            $homeForm.Controls.Add($lblUpd)
            $lblUpd.BringToFront()
            $estadoNotificacao.Link = $lblUpd
            & $posicionarRodape
        }
        $msg = "Nova versão do Concilia disponível: $($Upd.Versao) (atual: $versaoAtual)."
        if ($Upd.Notas) { $msg += "`n`n$($Upd.Notas)" }
        $msg += "`n`nAtualizar agora?"
        $r = [System.Windows.Forms.MessageBox]::Show($msg, "Atualização disponível", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { Invoke-AtualizacaoApp -InstallerUrl $urlInstalador }
    }.GetNewClosure()

    $homeForm.Add_Resize({ & $posicionarRodape }.GetNewClosure())

    $lblVerificar.Add_Click({
        $textoOriginal = $lblVerificar.Text
        $lblVerificar.Text = "Verificando..."
        $lblVerificar.Enabled = $false
        $mainForm.Cursor = "WaitCursor"
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $upd = Test-AtualizacaoDisponivel
            Set-AtualizacaoInfoCache -Info $upd
            if ($upd.Disponivel) {
                & $tratarAtualizacaoEncontrada $upd
            } else {
                [System.Windows.Forms.MessageBox]::Show("Você já está na versão mais recente (v$versaoAtual).", "Verificar atualizações", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        } finally {
            $lblVerificar.Text = $textoOriginal
            $lblVerificar.Enabled = $true
            $mainForm.Cursor = "Default"
        }
    }.GetNewClosure())

    # Checagem periodica: alem do aviso ao abrir a Home, reforca durante o uso - se o app
    # ficar aberto o dia todo (a janela unica nunca fecha/reabre entre navegacoes, ver
    # Navigate-Forward/Navigate-Back) e uma versao nova for publicada nesse meio tempo, o
    # usuario fica sabendo sem precisar fechar e reabrir o app. So mostra o popup uma vez por
    # versao nova (nao repete a cada tick pra mesma versao ja avisada, mas avisa de novo se
    # sair uma versao mais nova ainda depois).
    $timerAtualizacao = New-Object System.Windows.Forms.Timer
    $timerAtualizacao.Interval = 30 * 60 * 1000
    $timerAtualizacao.Add_Tick({
        $upd = Test-AtualizacaoDisponivel
        Set-AtualizacaoInfoCache -Info $upd
        if ($upd.Disponivel -and $upd.Versao -ne $estadoNotificacao.UltimaVersaoAvisada) { & $tratarAtualizacaoEncontrada $upd }
    }.GetNewClosure())
    $timerAtualizacao.Start()
    $mainForm.Add_FormClosed({ $timerAtualizacao.Stop(); $timerAtualizacao.Dispose() }.GetNewClosure())

    # Equivalente ao antigo Add_Shown do Form da Home (agora ela e um Panel, que nao tem esse
    # evento): dispara so quando a JANELA (persistente, unica) aparece pela primeira vez -
    # $mainForm.Shown acontece uma unica vez em toda a execucao do app, bem no instante em que
    # a Home e mostrada pela primeira vez, e nunca mais depois disso.
    $mainForm.Add_Shown({
        & $posicionarRodape
        $upd = Get-AtualizacaoInfoCache
        if ($upd.Disponivel) { & $tratarAtualizacaoEncontrada $upd }
    }.GetNewClosure())

    return $homeForm
}

function Navigate-Forward {
    # Vai da tela atual pra uma nova (ex.: Home -> Relatorios, Relatorios -> Conciliacao):
    # constroi o novo Panel, guarda o atual (sem descartar - so tira do content-root e empilha,
    # exatamente como o antigo $form.Hide() preservava o Form anterior) e mostra o novo no
    # lugar. So mexe no content-root se o novo Panel construir sem erro, senao a tela atual
    # nem pisca.
    param($PanelBuilder, [string]$Titulo)
    try {
        $novo = & $PanelBuilder
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Erro ao abrir: $($_.Exception.Message)", "Erro") | Out-Null
        return
    }
    if ($Script:ContentRoot.Controls.Count -gt 0) {
        $atual = $Script:ContentRoot.Controls[0]
        $Script:ContentRoot.Controls.Remove($atual)
        $Script:TelaStack.Push([PSCustomObject]@{ Panel = $atual; Titulo = $Script:MainForm.Text })
    }
    $Script:ContentRoot.Controls.Add($novo)
    $Script:MainForm.Text = $Titulo
}

function Navigate-Back {
    # Volta pra tela anterior (empilhada em Navigate-Forward): descarta a tela atual de
    # verdade (Dispose - equivalente ao antigo $modForm.Dispose() apos o ShowDialog retornar,
    # libera Timers/handlers dela) e desempilha a anterior, que estava so guardada, nunca
    # reconstruida - preserva seu estado exatamente como o antigo $form.Show() reexibia o
    # mesmo Form de antes. Sem efeito na tela raiz (Home), que nunca e empilhada por cima de
    # nada, entao a pilha fica vazia quando ela e a unica tela aberta.
    if ($Script:TelaStack.Count -eq 0) { return }
    if ($Script:ContentRoot.Controls.Count -gt 0) {
        $atual = $Script:ContentRoot.Controls[0]
        $Script:ContentRoot.Controls.Remove($atual)
        $atual.Dispose()
    }
    $anterior = $Script:TelaStack.Pop()
    $Script:ContentRoot.Controls.Add($anterior.Panel)
    $Script:MainForm.Text = $anterior.Titulo
}

function Start-App {
    # Janela unica do app: ao contrario do modelo antigo (cada tela era um Form separado,
    # aberto com ShowDialog por cima do anterior escondido, e fechado/Dispose ao clicar
    # Voltar), $Script:MainForm e criado uma unica vez aqui e nunca fecha durante a navegacao -
    # o usuario reportou que o app parecia "fechar e reabrir com um tamanho de janela
    # diferente" a cada tela visitada, o que era exatamente esse comportamento (cada Form novo
    # nascia com seu proprio tamanho calculado, ignorando o anterior). Agora so o CONTEUDO
    # dentro de $Script:ContentRoot troca (ver Navigate-Forward/Navigate-Back) - o tamanho da
    # janela e uma propriedade de UMA janela so, entao nunca muda sozinho entre telas.
    $Script:MainForm = New-Object System.Windows.Forms.Form
    # AutoScaleMode = None: os controles usam exatamente os pixels definidos no codigo. (Dpi
    # fazia o Windows Forms re-escalar tudo em cima da escala que ja calculamos manualmente
    # pela resolucao da tela, empurrando botoes e colunas para muito alem da janela visivel.)
    $Script:MainForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $Script:MainForm.BackColor = $Script:DS.SurfacePage
    $Script:MainForm.FormBorderStyle = "Sizable"
    $Script:MainForm.MaximizeBox = $true
    $Script:MainForm.StartPosition = "CenterScreen"
    $Script:MainForm.MinimumSize = New-Object System.Drawing.Size(700, 450)
    $Script:MainForm.Size = New-Object System.Drawing.Size(1000, 720)
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $Script:MainForm.Size = New-Object System.Drawing.Size([Math]::Min(1100, $wa.Width - 40), [Math]::Min(800, $wa.Height - 40))
    } catch {}

    $Script:ContentRoot = New-Object System.Windows.Forms.Panel
    $Script:ContentRoot.Dock = "Fill"
    $Script:ContentRoot.BackColor = $Script:DS.SurfacePage
    $Script:MainForm.Controls.Add($Script:ContentRoot)

    $Script:TelaStack = New-Object System.Collections.Generic.Stack[PSCustomObject]

    $painelHome = New-HomePanel
    $Script:ContentRoot.Controls.Add($painelHome)
    $Script:MainForm.Text = "Concilia"
    $iconeJanela = Get-AppFormIcon
    if ($iconeJanela) { $Script:MainForm.Icon = $iconeJanela }

    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::Run($Script:MainForm)
}

function Start-AppSTA {
    # OpenFileDialog/SaveFileDialog exigem uma thread STA. O compilador (ps2exe) nem sempre
    # garante isso de forma confiavel no processo final, entao forcamos aqui: se a thread atual
    # nao for STA, criamos uma thread dedicada com ApartmentState=STA para rodar o formulario.
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA) {
        Start-App
    } else {
        $t = New-Object System.Threading.Thread([System.Threading.ThreadStart] { Start-App })
        $t.SetApartmentState([System.Threading.ApartmentState]::STA)
        $t.Start()
        $t.Join()
    }
}

$Script:IsDotSourced = $MyInvocation.InvocationName -eq '.'
if (-not $Script:IsDotSourced) {
    Start-AppSTA
}

