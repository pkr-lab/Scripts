<#
.SYNOPSIS
Erste-Einrichtung: Erstellt Verzeichnisstruktur und prueft Voraussetzungen.

.DESCRIPTION
Wird einmalig bei Ersteinrichtung ausgefuehrt (nicht durch den Watchdog,
da er im StartUp-Ordner liegt, der vom Watchdog ausgeschlossen wird).
Stellt sicher, dass die benoetigten Basisordner existieren und
erstellt eine Software-Inventur des Systems.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Modul laden & Logging starten
# ---------------------------------------------------------

$modulePath = Join-Path $PSScriptRoot '..\Logging.psm1'
Import-Module $modulePath -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\Common.psm1') -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "=== Erste-Einrichtung gestartet ==="

# ---------------------------------------------------------
# Verzeichnisstruktur sicherstellen
# ---------------------------------------------------------

$baseDirs = @(
    "C:\Users\Public\10020115_WinScripts\Logs",
    "C:\Users\Public\10020115_WinScripts\Win11_C"
)

foreach ($dir in $baseDirs) {
    if (-not (Test-Path $dir)) {
        try {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Log -Level INFO -Message "Verzeichnis erstellt: $dir"
        } catch {
            Write-Log -Level WARN -Message "Verzeichnis konnte nicht erstellt werden: $dir - $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level DEBUG -Message "Verzeichnis vorhanden: $dir"
    }
}

# ---------------------------------------------------------
# Software-Inventur
# ---------------------------------------------------------

Write-Log -Level INFO -Message "=== Software-Inventur ==="

try {
    $sorted = @(Get-InstalledProgram | Sort-Object Name)
    if ($sorted.Count -eq 0) {
        Write-Log -Level WARN -Message "Keine klassischen Programme gefunden."
    } else {
        Write-Log -Level INFO -Message "Klassische Programme: $($sorted.Count) gefunden."
        foreach ($app in $sorted) {
            Write-Log -Level INFO -Message "  $($app.Name) | v$($app.Version) | $($app.Publisher)"
        }
    }
} catch {
    Write-Log -Level ERROR -Message "Fehler bei klassischen Programmen: $($_.Exception.Message)"
}

try {
    $uwpApps = Get-AppxPackage -ErrorAction Stop | Sort-Object Name
    Write-Log -Level INFO -Message "UWP/Store-Apps: $($uwpApps.Count) gefunden."
    foreach ($app in $uwpApps) {
        Write-Log -Level INFO -Message "  UWP: $($app.Name) | v$($app.Version)"
    }
} catch {
    Write-Log -Level ERROR -Message "Fehler bei UWP-Apps: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "=== Erste-Einrichtung abgeschlossen ==="
