Import-Module ps2exe -Force

$appExe = Join-Path $PSScriptRoot "Concilia.exe"
if (-not (Test-Path $appExe)) { throw "Concilia.exe nao encontrado - rode build.ps1 primeiro." }

$templatePath = Join-Path $PSScriptRoot "Installer.template.ps1"
$generatedPath = Join-Path $PSScriptRoot "Installer.generated.ps1"
$outExe = Join-Path $PSScriptRoot "Concilia_Instalador.exe"

Write-Host "Lendo $appExe ($((Get-Item $appExe).Length) bytes) e codificando em Base64..."
$bytes = [System.IO.File]::ReadAllBytes($appExe)
$b64 = [System.Convert]::ToBase64String($bytes)

$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
$generated = $template.Replace("__PAYLOAD_BASE64__", $b64)
$utf8bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($generatedPath, $generated, $utf8bom)
Write-Host "Script do instalador gerado: $generatedPath ($((Get-Item $generatedPath).Length) bytes)"

if (Test-Path $outExe) { Remove-Item $outExe -Force }
Invoke-ps2exe -inputFile $generatedPath -outputFile $outExe `
    -iconFile (Join-Path $PSScriptRoot "app.ico") `
    -title "Instalador - Concilia" `
    -product "Concilia - Instalador" `
    -version "1.0.0.0" `
    -noConsole `
    -requireAdmin:$false

if (Test-Path $outExe) {
    Write-Host "Instalador gerado: $outExe"
    Get-Item $outExe | Select-Object Name, Length, LastWriteTime
} else {
    Write-Host "FALHA ao gerar o instalador"
}

