# Modul laden
$modulePath = Join-Path $PSScriptRoot '..\Logging.psm1'
Import-Module $modulePath -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\Common.psm1') -ErrorAction Stop

Initialize-Logger -Level "INFO"

Write-Log -Level INFO -Message "=== Software-Inventur gestartet ==="

# === Klassische Programme ===
Write-Log -Level INFO -Message "=== Klassische Programme ==="

try {
    $classicApps = @(Get-InstalledProgram)

    if ($classicApps.Count -eq 0) {
        Write-Log -Level WARN -Message "Keine klassischen Programme gefunden."
    }
    else {
        foreach ($app in $classicApps | Sort-Object Name) {
            Write-Log -Level INFO -Message "Programm: $($app.Name) | Version: $($app.Version) | Publisher: $($app.Publisher)"
        }
    }
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Auslesen klassischer Programme: $($_.Exception.Message)"
}

# === UWP / Store Apps ===
Write-Log -Level INFO -Message "=== UWP / Store Apps ==="

try {
    $uwpApps = Get-AppxPackage |
        Select-Object Name, Version, Publisher |
        Sort-Object Name

    foreach ($app in $uwpApps) {
        Write-Log -Level INFO -Message "UWP-App: $($app.Name) | Version: $($app.Version) | Publisher: $($app.Publisher)"
    }
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Auslesen der UWP-Apps: $($_.Exception.Message)"
}

Write-Log -Level INFO -Message "=== Software-Inventur abgeschlossen ==="
