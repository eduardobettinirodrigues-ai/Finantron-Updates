#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms

# $appName e so o nome da PASTA de instalacao (%LOCALAPPDATA%\ConciliacaoVendas) - ficou como
# era antes da troca de nome pra Concilia de proposito: e la que ficam config.json e
# config_fechamento.json (mapeamento de terminais, senha), entao renomear a pasta perderia as
# configuracoes de quem ja tem o app instalado. O que o usuario ve (exe, atalhos, titulos)
# ja usa o nome novo.
$appName = "ConciliacaoVendas"
$appTitle = "Concilia"
$exeName = "Concilia.exe"
$processoNome = "Concilia"
# Nomes de exe/processo e de atalhos de versoes anteriores - removidos na instalacao pra nao
# sobrar um icone/arquivo duplicado ao lado do novo.
$exeAntigo = "ConciliacaoVendas.exe"
$processoAntigo = "ConciliacaoVendas"
$shortcutName = "Concilia"
$shortcutNamesAntigos = @("Finantron 3000", "ConciliacaoVendas")

try {
    $installDir = Join-Path $env:LOCALAPPDATA $appName
    $exePath = Join-Path $installDir $exeName
    $exeAntigoPath = Join-Path $installDir $exeAntigo
    $isUpdate = (Test-Path $exePath) -or (Test-Path $exeAntigoPath)

    # Se o programa estiver aberto, o arquivo fica travado e a atualizacao falharia
    # silenciosamente. Avisa e oferece para fechar antes de continuar.
    $rodando = Get-Process -Name @($processoNome, $processoAntigo) -ErrorAction SilentlyContinue
    if ($rodando) {
        $resp = [System.Windows.Forms.MessageBox]::Show(
            "O $appTitle esta aberto. Preciso fecha-lo para instalar a atualizacao.`n`nFechar agora e continuar?",
            $appTitle, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($resp -ne [System.Windows.Forms.DialogResult]::Yes) {
            [System.Windows.Forms.MessageBox]::Show("Instalacao cancelada. Feche o programa e rode o instalador novamente.", $appTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $rodando | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }

    $exeBytes = [System.Convert]::FromBase64String("__PAYLOAD_BASE64__")
    [System.IO.File]::WriteAllBytes($exePath, $exeBytes)
    if (Test-Path $exeAntigoPath) { Remove-Item $exeAntigoPath -Force -ErrorAction SilentlyContinue }

    $wshell = New-Object -ComObject WScript.Shell

    $desktop = [Environment]::GetFolderPath("Desktop")
    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"

    # Remove atalhos com o nome antigo (de instalacoes anteriores) pra nao deixar um icone
    # duplicado/desatualizado ao lado do novo, renomeado.
    foreach ($pasta in @($desktop, $startMenu)) {
        if (-not (Test-Path $pasta)) { continue }
        foreach ($nomeAntigo in $shortcutNamesAntigos) {
            if ($nomeAntigo -eq $shortcutName) { continue }
            $antigo = Join-Path $pasta "$nomeAntigo.lnk"
            if (Test-Path $antigo) { Remove-Item $antigo -Force -ErrorAction SilentlyContinue }
        }
    }

    $lnkDesktop = $wshell.CreateShortcut((Join-Path $desktop "$shortcutName.lnk"))
    $lnkDesktop.TargetPath = $exePath
    $lnkDesktop.WorkingDirectory = $installDir
    $lnkDesktop.IconLocation = "$exePath,0"
    $lnkDesktop.Description = $appTitle
    $lnkDesktop.Save()

    try {
        if (Test-Path $startMenu) {
            $lnkStart = $wshell.CreateShortcut((Join-Path $startMenu "$shortcutName.lnk"))
            $lnkStart.TargetPath = $exePath
            $lnkStart.WorkingDirectory = $installDir
            $lnkStart.IconLocation = "$exePath,0"
            $lnkStart.Description = $appTitle
            $lnkStart.Save()
        }
    } catch {}

    if ($isUpdate) {
        $msg = "Atualizacao concluida!`n`nO programa em $installDir foi atualizado para a versao mais recente. Suas configuracoes salvas (mapeamento de terminais, senha) foram mantidas."
    } else {
        $msg = "Instalacao concluida!`n`nO programa foi instalado em:`n$installDir`n`nUm atalho foi criado na Area de Trabalho e no Menu Iniciar."
    }
    [System.Windows.Forms.MessageBox]::Show($msg, $appTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

    $resp = [System.Windows.Forms.MessageBox]::Show(
        "Deseja abrir o programa agora?", $appTitle,
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($resp -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process $exePath
    }
} catch {
    [System.Windows.Forms.MessageBox]::Show("Falha na instalacao: $($_.Exception.Message)", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
