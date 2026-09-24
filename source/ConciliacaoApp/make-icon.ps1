# Gera app.ico (icone do exe/atalhos do Concilia) a partir do logo desenhado em App.ps1
# (New-ConciliaLogoBitmap, modo Tile). Rode de novo so se o logo mudar - o app.ico gerado e
# o que build.ps1 embute no exe via ps2exe.
#
# Formato: tamanhos pequenos (16-48) em BMP/DIB 32 bits e so o de 256 em PNG - o mesmo esquema do
# ICO classico do Windows, que o compilador do ps2exe e o Explorer aceitam em qualquer versao.

. (Join-Path $PSScriptRoot "App.ps1")

$tamanhos = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = @()
foreach ($t in $tamanhos) {
    $bmp = New-ConciliaLogoBitmap -Tamanho $t -Modo Tile
    $ms = New-Object System.IO.MemoryStream
    if ($t -ge 256) {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        $bw = New-Object System.IO.BinaryWriter $ms
        # BITMAPINFOHEADER (altura dobrada: XOR + mascara AND)
        $bw.Write([int]40); $bw.Write([int]$t); $bw.Write([int]($t * 2))
        $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]0)
        $bw.Write([int]($t * $t * 4)); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
        for ($y = $t - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $t; $x++) {
                $c = $bmp.GetPixel($x, $y)
                $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A)
            }
        }
        $linhaAnd = [int]([Math]::Ceiling($t / 32.0) * 4)
        $bw.Write([byte[]]::new($linhaAnd * $t))
        $bw.Flush()
    }
    $frames += [PSCustomObject]@{ Tamanho = $t; Bytes = $ms.ToArray() }
    $bmp.Dispose()
}

$saida = Join-Path $PSScriptRoot "app.ico"
$fs = [System.IO.File]::Create($saida)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $dim = if ($f.Tamanho -ge 256) { 0 } else { $f.Tamanho }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]$f.Bytes.Length); $w.Write([int]$offset)
    $offset += $f.Bytes.Length
}
foreach ($f in $frames) { $w.Write($f.Bytes) }
$w.Flush(); $fs.Close()
Write-Host "Gerado: $saida ($((Get-Item $saida).Length) bytes, $($frames.Count) tamanhos)"

