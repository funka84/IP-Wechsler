param(
    [string]$OutputName = "IP_Wechsler.exe"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $scriptRoot "IP_Wechsler.ps1"
$target = Join-Path $scriptRoot $OutputName

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installiere Modul ps2exe (CurrentUser)..."
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe

Invoke-PS2EXE -InputFile $source -OutputFile $target -noConsole -STA -title "IP-Adresse Wechsler"

Write-Host "EXE erstellt: $target"
Write-Host "Hinweis: presets.json muss im gleichen Ordner wie die EXE liegen."
