Import-Module ps2exe -Force

$src = Join-Path $PSScriptRoot "App.ps1"
$out = Join-Path $PSScriptRoot "Concilia.exe"

if (Test-Path $out) { Remove-Item $out -Force }

$icon = Join-Path $PSScriptRoot "app.ico"

Invoke-ps2exe -inputFile $src -outputFile $out `
    -iconFile $icon `
    -title "Concilia" `
    -product "Concilia" `
    -version "1.0.0.0" `
    -company "" `
    -copyright "" `
    -noConsole `
    -STA `
    -requireAdmin:$false

if (Test-Path $out) {
    Write-Host "EXE gerado: $out"
    Get-Item $out | Select-Object Name, Length, LastWriteTime
} else {
    Write-Host "FALHA ao gerar o EXE"
}

