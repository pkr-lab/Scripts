<#
.SYNOPSIS
Findet ein Gerät anhand seiner MAC-Adresse im lokalen Netzwerk und baut eine SSH-Verbindung auf.

.PARAMETER TargetMac
MAC-Adresse des Zielgeräts im Format XX-XX-XX-XX-XX-XX (Windows ARP-Format). Standard: SshZielMac aus Konfiguration.psd1.

.PARAMETER SshUser
SSH-Benutzername. Standard: aktueller Windows-Benutzername.
#>
param(
    [string]$TargetMac = "",
    [string]$SshUser   = $env:USERNAME
)

$ErrorActionPreference = "Stop"

if (-not $TargetMac) {
    Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -ErrorAction Stop
    try {
        $TargetMac = (Get-Konfiguration -Pflichtwert SshZielMac).SshZielMac
    } catch {
        Write-Host "FEHLER: $($_.Exception.Message)"
        exit 1
    }
}

function Find-IpByMac {
    param([string]$Mac)

    # ARP-Tabelle auslesen und nach MAC-Adresse suchen
    # Windows ARP-Format: "  192.168.1.1          aa-bb-cc-dd-ee-ff     dynamisch"
    $arpOutput = arp -a
    $macLower  = $Mac.ToLower()

    foreach ($line in $arpOutput) {
        if ($line.ToLower() -match $macLower) {
            # Erste Spalte = IP-Adresse (nach führendem Whitespace)
            $ip = ($line.Trim() -split '\s+')[0]
            if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                return $ip
            }
        }
    }
    return $null
}

function Get-LocalSubnet {
    $ipInfo = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
              Select-Object -First 1

    if (-not $ipInfo) { return $null, $null }
    return $ipInfo.IPAddress, $ipInfo.PrefixLength
}

function Invoke-PingSweep {
    param([string]$BaseIp)

    Write-Host "Starte Ping-Sweep auf $BaseIp.1-254 ..."
    $prefix = $BaseIp.Substring(0, $BaseIp.LastIndexOf('.') + 1)

    1..254 | ForEach-Object {
        Start-Process -FilePath "ping.exe" `
            -ArgumentList "-n 1 -w 100 $prefix$_" `
            -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3  # Antworten abwarten
}

# ---------------------------------------------------------
# Hauptlogik
# ---------------------------------------------------------

Write-Host "Suche Geraet mit MAC-Adresse: $TargetMac"

# Broadcast-Ping zur ARP-Cache-Aktualisierung
try { ping -n 2 255.255.255.255 2>$null | Out-Null } catch { Write-Verbose "Broadcast-Ping fehlgeschlagen: $($_.Exception.Message)" }

$ip = Find-IpByMac -Mac $TargetMac

if (-not $ip) {
    Write-Host "Nicht im ARP-Cache. Starte erweiterten Scan..."

    $localIp, $prefix = Get-LocalSubnet

    if (-not $localIp) {
        Write-Host "FEHLER: Keine aktive Netzwerkverbindung gefunden."
        exit 1
    }

    Write-Host "Lokale IP: $localIp / Praefix: $prefix"

    if (Get-Command nmap -ErrorAction SilentlyContinue) {
        $subnet = "$localIp/$prefix"
        Write-Host "Nutze nmap fuer Subnetz-Scan: $subnet"
        nmap -sn $subnet | Out-Null
    } else {
        Write-Host "nmap nicht gefunden. Nutze Ping-Sweep..."
        Invoke-PingSweep -BaseIp $localIp
    }

    $ip = Find-IpByMac -Mac $TargetMac
}

if (-not $ip) {
    Write-Host "FEHLER: Geraet mit MAC $TargetMac nicht gefunden."
    exit 1
}

Write-Host "Gefundene IP: $ip"
Write-Host "Starte SSH als $SshUser@$ip ..."

ssh "$SshUser@$ip"
