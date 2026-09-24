# Publica uma nova versao do Concilia no repositorio de atualizacoes
# (github.com/eduardobettinirodrigues-ai/Finantron-Updates), via API do GitHub - nao precisa
# de git/gh instalados, so o token em github_token.txt (mesma pasta deste script).
#
# Uso: .\publish-update.ps1 -Versao "1.5.1" -Notas "Corrige X, adiciona Y"
#
# O que faz:
#   1. Recusa se a versao nao for MAIOR que a ja publicada (impede uma copia desatualizada do
#      projeto de sobrescrever a versao de outra pessoa). -Forcar ignora isso.
#   2. Publica o instalador e depois o version.json (nessa ordem: o app so ve a versao nova
#      quando o instalador dela ja esta no ar).
#   3. Sobe o codigo-fonte (App.ps1, scripts, design-system, docs) pra pasta source/ do mesmo
#      repositorio - e dai que os outros PCs pegam o codigo mais novo com sync-source.ps1,
#      pra todo mundo trabalhar sempre em cima da ultima versao. Arquivos que nao mudaram
#      nao geram commit.

param(
    [Parameter(Mandatory)] [string]$Versao,
    [string]$Notas = "",
    [string]$InstaladorPath = "",
    [string]$TokenPath = "",
    [switch]$Forcar,
    [switch]$SoFonte   # so sobe o codigo-fonte pra source/ (sem instalador nem version.json)
)

$dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $InstaladorPath) { $InstaladorPath = Join-Path $dir "Concilia_Instalador.exe" }
if (-not $TokenPath) { $TokenPath = Join-Path $dir "github_token.txt" }
$raiz = Split-Path -Parent $dir

$owner = "eduardobettinirodrigues-ai"
$repo = "Finantron-Updates"
$branch = "main"

# Token: variavel de ambiente UPDATES_TOKEN ou, se nao houver, o arquivo github_token.txt.
if (-not $env:UPDATES_TOKEN -and -not (Test-Path $TokenPath)) {
    throw "Token nao encontrado em '$TokenPath'. Crie um Personal Access Token (fine-grained, permissao Contents: Read and write, so nesse repositorio) em github.com > Settings > Developer settings, e salve o valor nesse arquivo (so o token, sem mais nada)."
}
if (-not (Test-Path $InstaladorPath)) {
    throw "Instalador nao encontrado em '$InstaladorPath'. Rode build.ps1 e build-installer.ps1 antes."
}

$token = if ($env:UPDATES_TOKEN) { $env:UPDATES_TOKEN.Trim() } else { (Get-Content $TokenPath -Raw).Trim() }
$headers = @{ Authorization = "Bearer $token"; "User-Agent" = "ConciliaPublisher"; Accept = "application/vnd.github+json" }

function Get-GitBlobSha([byte[]]$Bytes) {
    # SHA1 no formato de blob do git ("blob <tamanho>\0<conteudo>") - o mesmo "sha" que a API
    # devolve, pra saber se um arquivo mudou sem baixar.
    $cab = [System.Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
    $tudo = New-Object byte[] ($cab.Length + $Bytes.Length)
    [Array]::Copy($cab, 0, $tudo, 0, $cab.Length)
    [Array]::Copy($Bytes, 0, $tudo, $cab.Length, $Bytes.Length)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    return ([BitConverter]::ToString($sha1.ComputeHash($tudo)) -replace '-', '').ToLower()
}

function Publish-Arquivo {
    param([string]$CaminhoRepo, [byte[]]$Bytes, [string]$Mensagem, [switch]$PularSeIgual)
    $url = "https://api.github.com/repos/$owner/$repo/contents/$CaminhoRepo"
    $sha = $null
    try {
        $existing = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        $sha = $existing.sha
    } catch {
        # 404 = arquivo ainda nao existe no repo (primeira publicacao) - segue sem sha, cria novo.
    }
    if ($PularSeIgual -and $sha -and $sha -eq (Get-GitBlobSha $Bytes)) { return $false }
    $body = @{ message = $Mensagem; content = [Convert]::ToBase64String($Bytes); branch = $branch }
    if ($sha) { $body.sha = $sha }
    $json = $body | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Headers $headers -Method Put -Body $json -ContentType "application/json; charset=utf-8" | Out-Null
    Write-Host "  Publicado: $CaminhoRepo ($($Bytes.Length) bytes)"
    return $true
}

# 1) Versao precisa ser maior que a publicada (lida pela API, nao pelo raw, que atrasa).
$versaoPublicada = $null
if (-not $SoFonte) { try {
    $atual = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/version.json" -Headers $headers -ErrorAction Stop
    $versaoPublicada = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($atual.content -replace '\s', ''))) | ConvertFrom-Json).versao
} catch { $versaoPublicada = $null } }
if ($versaoPublicada -and -not $Forcar -and ([version]$Versao -le [version]$versaoPublicada)) {
    throw "A versao $Versao nao e maior que a ja publicada ($versaoPublicada). Rode sync-source.ps1 pra pegar o codigo mais novo, suba `$Script:AppVersion no App.ps1 e gere o build de novo (ou use -Forcar)."
}

# 2) Instalador e version.json
if (-not $SoFonte) {
Write-Host "Publicando Concilia v$Versao..."
# O arquivo no repositorio mantem o nome antigo (ConciliacaoVendas_Instalador.exe) de proposito:
# e a URL que os apps ja instalados (ate a 1.4.5) tem gravada pra baixar a atualizacao.
Publish-Arquivo -CaminhoRepo "ConciliacaoVendas_Instalador.exe" -Bytes ([System.IO.File]::ReadAllBytes($InstaladorPath)) -Mensagem "v$Versao - instalador" | Out-Null
$versaoJson = @{ versao = $Versao; notas = $Notas } | ConvertTo-Json
Publish-Arquivo -CaminhoRepo "version.json" -Bytes ([System.Text.Encoding]::UTF8.GetBytes($versaoJson)) -Mensagem "v$Versao" | Out-Null
}

# 3) Codigo-fonte em source/ (test-run.ps1 fica de fora: tem a senha do arquivo C6 de teste;
#    github_token.txt e dados/planilhas obviamente tambem nao sobem).
$arquivosFonte = @(
    "ConciliacaoApp\App.ps1", "ConciliacaoApp\Installer.template.ps1", "ConciliacaoApp\build.ps1",
    "ConciliacaoApp\build-installer.ps1", "ConciliacaoApp\publish-update.ps1",
    "ConciliacaoApp\sync-source.ps1", "ConciliacaoApp\make-icon.ps1", "ConciliacaoApp\app.ico",
    "CLAUDE.md", "README.md", "Finantron3000_Escopo_Design.md"
)
$arquivosFonte += Get-ChildItem (Join-Path $raiz "design-system") -File -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName.Substring($raiz.Length + 1) }
$enviados = 0
foreach ($rel in $arquivosFonte) {
    $abs = Join-Path $raiz $rel
    if (-not (Test-Path $abs)) { continue }
    $caminhoRepo = "source/" + ($rel -replace '\\', '/')
    if (Publish-Arquivo -CaminhoRepo $caminhoRepo -Bytes ([System.IO.File]::ReadAllBytes($abs)) -Mensagem "v$Versao - fonte" -PularSeIgual) { $enviados++ }
}
Write-Host "Codigo-fonte: $enviados arquivo(s) atualizado(s) em source/."
if (-not $SoFonte) { Write-Host "Concluido. PCs com o app aberto vao ver o aviso de atualizacao na proxima vez que abrirem a tela inicial." }
