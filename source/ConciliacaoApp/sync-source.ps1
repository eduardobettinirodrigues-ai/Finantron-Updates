# Baixa o codigo-fonte mais recente (a pasta source/ do repositorio de atualizacoes, que o
# publish-update.ps1 alimenta a cada publicacao) e sobrescreve os arquivos locais.
# RODE ISTO ANTES DE COMECAR QUALQUER MUDANCA - assim todo mundo trabalha em cima da ultima
# versao publicada e uma pessoa nao desfaz o trabalho da outra.
#
# Uso: .\sync-source.ps1        (-SoListar mostra o que mudaria, sem gravar nada)
# Atencao: sobrescreve alteracoes locais ainda nao publicadas nesses arquivos.

param([switch]$SoListar)

$dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$raiz = Split-Path -Parent $dir
$tokenPath = Join-Path $dir "github_token.txt"
$owner = "eduardobettinirodrigues-ai"; $repo = "Finantron-Updates"; $branch = "main"

$token = if ($env:UPDATES_TOKEN) { $env:UPDATES_TOKEN.Trim() } elseif (Test-Path $tokenPath) { (Get-Content $tokenPath -Raw).Trim() } else { throw "Sem token: coloque github_token.txt ao lado deste script." }
$headers = @{ Authorization = "Bearer $token"; "User-Agent" = "ConciliaSync"; Accept = "application/vnd.github+json" }

function Get-GitBlobSha([byte[]]$Bytes) {
    $cab = [System.Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
    $tudo = New-Object byte[] ($cab.Length + $Bytes.Length)
    [Array]::Copy($cab, 0, $tudo, 0, $cab.Length)
    [Array]::Copy($Bytes, 0, $tudo, $cab.Length, $Bytes.Length)
    return ([BitConverter]::ToString([System.Security.Cryptography.SHA1]::Create().ComputeHash($tudo)) -replace '-', '').ToLower()
}

$arvore = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/git/trees/${branch}?recursive=1" -Headers $headers
$fontes = $arvore.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "source/*" }
if (-not $fontes) { Write-Host "Nada em source/ ainda - o primeiro publish-update.ps1 cria essa pasta."; return }

$alterados = 0
foreach ($f in $fontes) {
    $rel = $f.path.Substring("source/".Length)
    $destino = Join-Path $raiz ($rel -replace '/', '\')
    if ((Test-Path $destino) -and (Get-GitBlobSha ([System.IO.File]::ReadAllBytes($destino))) -eq $f.sha) { continue }
    $alterados++
    if ($SoListar) { Write-Host "  mudaria: $rel"; continue }
    $blob = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/git/blobs/$($f.sha)" -Headers $headers
    $bytes = [Convert]::FromBase64String(($blob.content -replace '\s', ''))
    $pasta = Split-Path -Parent $destino
    if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($destino, $bytes)
    Write-Host "  atualizado: $rel"
}
Write-Host "$alterados arquivo(s) $(if ($SoListar) { 'diferentes' } else { 'atualizado(s)' }) (de $($fontes.Count) em source/)."
