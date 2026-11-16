#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =====================================================================
#  Logging-Modul laden
# =====================================================================
$modulePath = Join-Path $PSScriptRoot '..\Logging.psm1'
Import-Module -Name $modulePath -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot '..\Common.psm1') -ErrorAction Stop

Initialize-Logger -Level 'INFO'
Write-Log -Level INFO -Message "Scriptstart: Geraetepruefung & BIOS-Tool-Installation"

# =====================================================================
#  Helper-Funktionen
# =====================================================================

function Test-HasHPCMSL {
    if (Get-InstalledModule -Name 'HPCMSL' -ErrorAction SilentlyContinue) { return $true }
    if (Get-Module -ListAvailable -Name 'HPCMSL')                         { return $true }
    return $false
}

function Install-LenovoSystemUpdate {
    param(
        [string]$InstallerPath = "LenovoBiosInstall\system_update.exe"
    )

    if (-not (Test-Path $InstallerPath)) {
        Write-Log -Level ERROR -Message "Lenovo Installer nicht gefunden: $InstallerPath"
        throw "Lenovo Installer fehlt. Bitte von https://support.lenovo.com herunterladen."
    }

    Write-Log -Level INFO -Message "Starte Lenovo System Update Installation: $InstallerPath"
    Start-Process -FilePath $InstallerPath -ArgumentList "/VERYSILENT /NORESTART" -Wait -ErrorAction Stop
    Write-Log -Level INFO -Message "Lenovo System Update erfolgreich installiert."
}

# =====================================================================
#  Gerätehersteller ermitteln
# =====================================================================

$manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer.Trim()
Write-Log -Level INFO -Message "Geraetehersteller erkannt: $manufacturer"

# =====================================================================
#  Hauptlogik
# =====================================================================

try {
    switch -Wildcard ($manufacturer) {

        "HP*" {
            Write-Log -Level INFO -Message "HP-Geraet erkannt – pruefe HPCMSL..."

            if (Test-HasHPCMSL) {
                Write-Log -Level INFO -Message "HPCMSL bereits installiert. Kein Handlungsbedarf."
                exit 0
            }

            Write-Log -Level INFO -Message "HPCMSL nicht gefunden – Installation wird vorbereitet..."
            Write-Log -Level INFO -Message "Stelle Paket-Infrastruktur sicher (NuGet, PSGallery)..."
            Initialize-PackageInfrastructure
            Write-Log -Level INFO -Message "Paket-Infrastruktur bereit."

            $scope = if (Test-IsAdmin) { 'AllUsers' } else { 'CurrentUser' }
            Write-Log -Level INFO -Message "Installations-Scope: $scope"

            Install-Module -Name 'HPCMSL' -Scope $scope -Force -AcceptLicense -ErrorAction Stop
            Import-Module HPCMSL -ErrorAction Stop

            $ver = (Get-Module HPCMSL).Version
            Write-Log -Level INFO -Message "HPCMSL erfolgreich installiert. Version: $ver"
            exit 0
        }

        "Lenovo*" {
            Write-Log -Level INFO -Message "Lenovo-Geraet erkannt – installiere Lenovo System Update..."
            Install-LenovoSystemUpdate
            exit 0
        }

        default {
            Write-Log -Level WARN -Message "Unbekannter Hersteller '$manufacturer' – keine Installation durchgefuehrt."
            exit 0
        }
    }
} catch {
    Write-Log -Level ERROR -Message "Kritischer Fehler: $($_.Exception.Message)"
    exit 1
}
