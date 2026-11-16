function Test-IsAdmin {
    $identitaet = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal  = [Security.Principal.WindowsPrincipal]::new($identitaet)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledProgram {
    $pfade = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($pfad in $pfade) {
        if (-not (Test-Path $pfad)) {
            Write-Verbose "Registry-Pfad nicht gefunden: $pfad"
            continue
        }
        Get-ChildItem -Path $pfad -ErrorAction SilentlyContinue | ForEach-Object {
            $eintrag = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue |
                Select-Object -Property DisplayName, DisplayVersion, Publisher, InstallDate
            if ($eintrag -and $eintrag.DisplayName) {
                [PSCustomObject]@{
                    Name        = $eintrag.DisplayName
                    Version     = $eintrag.DisplayVersion
                    Publisher   = $eintrag.Publisher
                    InstallDate = $eintrag.InstallDate
                }
            }
        }
    }
}

function Initialize-PackageInfrastructure {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "TLS 1.2 konnte nicht gesetzt werden: $($_.Exception.Message)"
    }

    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop | Out-Null
    } catch {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    }

    try {
        $galerie = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
        if ($galerie.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
        }
    } catch {
        Register-PSRepository -Default -ErrorAction Stop
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
    }
}

function Get-Konfiguration {
    param(
        [string[]]$Pflichtwert = @(),
        [switch]$Optional,
        [string]$Pfad = (Join-Path $PSScriptRoot 'Konfiguration.psd1')
    )

    if (-not (Test-Path -LiteralPath $Pfad)) {
        if ($Optional) { return @{} }
        throw "Konfigurationsdatei fehlt: $Pfad (Vorlage: Konfiguration.example.psd1)"
    }

    $konfiguration = Import-PowerShellDataFile -LiteralPath $Pfad
    $fehlend = @($Pflichtwert | Where-Object {
        $wert = [string]$konfiguration[$_]
        [string]::IsNullOrWhiteSpace($wert) -or $wert -match '^<.*>$'
    })
    if ($fehlend.Count -gt 0) {
        throw "Konfigurationsdatei $Pfad ohne Wert fuer: $($fehlend -join ', ')"
    }
    return $konfiguration
}

Export-ModuleMember -Function Test-IsAdmin, Get-InstalledProgram, Initialize-PackageInfrastructure, Get-Konfiguration
