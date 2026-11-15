# ---------------------------------------------------------
# Logging-Modul laden
# ---------------------------------------------------------
Import-Module (Join-Path $PSScriptRoot '..\Logging.psm1') -ErrorAction Stop

# ---------------------------------------------------------
# Internetverbindung prüfen (mit Retry und Timeout)
# Wartezeit zwischen Versuchen standardmäßig 10 Sekunden
# ---------------------------------------------------------
function Test-InternetConnection {
    param(
        [int]$Retries = 5,
        [int]$DelaySeconds = 10,
        [int]$TimeoutSec = 10
    )

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri "https://www.google.com/generate_204" -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($resp.StatusCode -in 200,204) {
                Write-Log -Level "INFO" -Message "Internetverbindung erkannt (Versuch $i/$Retries)."
                return $true
            }
        }
        catch {
            Write-Log -Level "WARN" -Message "Keine Internetverbindung (Versuch $i/$Retries): $($_.Exception.Message)"
            if ($i -lt $Retries) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }

    Write-Log -Level "ERROR" -Message "Keine Internetverbindung nach $Retries Versuchen."
    return $false
}

# ---------------------------------------------------------
# Sicherstellen und Backup: Alle .ps1 Dateien konvertieren
# - Backup wird angelegt: <file>.bak.<timestamp>
# - Zielkodierung: UTF-16LE (Unicode) mit BOM (Windows PowerShell kompatibel)
# ---------------------------------------------------------
function Ensure-AllScriptsEncoding {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    if (-not (Test-Path $RootPath)) {
        Write-Log -Level "WARN" -Message "Ensure-AllScriptsEncoding: RootPath existiert nicht: $RootPath"
        return
    }

    $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
    $ps1Files = Get-ChildItem -Path $RootPath -Filter "*.ps1" -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $ps1Files) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $needsConversion = $true

            if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                # UTF-16 LE BOM vorhanden -> kompatibel
                $needsConversion = $false
            } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                # UTF-8 with BOM -> kompatibel
                $needsConversion = $false
            }

            if ($needsConversion) {
                $backupPath = "$($file.FullName).bak.$timestamp"
                Copy-Item -LiteralPath $file.FullName -Destination $backupPath -Force
                $content = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction Stop
                # Konvertiere zu UTF-16LE (Unicode) mit BOM
                $content | Out-File -LiteralPath $file.FullName -Encoding Unicode -Force
                Write-Log -Level "INFO" -Message "Konvertiert zu UTF-16LE und Backup erstellt: $($file.FullName) -> $backupPath"
            } else {
                Write-Log -Level "DEBUG" -Message "Kodierung OK: $($file.FullName)"
            }
        }
        catch {
            Write-Log -Level "WARN" -Message "Ensure-AllScriptsEncoding fehlgeschlagen: $($file.FullName) - $($_.Exception.Message)"
        }
    }
}

function Get-AutoRunScript {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot,
        [string[]]$ExcludedFolder = @()
    )

    $separator = [IO.Path]::DirectorySeparatorChar
    $root = [IO.Path]::GetFullPath($ScriptRoot).TrimEnd($separator) + $separator
    $excludedPrefixes = @($ExcludedFolder | ForEach-Object { $root + $_ + $separator })

    Get-ChildItem -Path $ScriptRoot -Filter "*.ps1" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $full = [IO.Path]::GetFullPath($_.FullName)
            $relative = $full.Substring($root.Length)
            if ($relative.IndexOf($separator) -lt 0) { return $false }
            $excluded = $excludedPrefixes | Where-Object { $full.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
            -not $excluded
        }
}

# ---------------------------------------------------------
# Logger initialisieren
# ---------------------------------------------------------
Initialize-Logger -Level "INFO" -FileName "log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Write-Log -Level INFO -Message "Starte kombinierten Import- und WatchDog-Prozess."

# ---------------------------------------------------------
# 0. Konfiguration
# ---------------------------------------------------------
$Source = "C:\Users\DLRG-JugendAndernach\DLRG\DLRG OG Andernach Projekte-Jugendnotebooks - Jugendnotebooks\Win11_C"
$DestinationRoot = "C:\Users\Public\10020115_WinScripts"
$Destination = Join-Path $DestinationRoot "Win11_C"

# Relativer Pfad zur Message-Script-Datei (relativ zu Source / Destination)
$MessageScriptRelative = "Software\Scripte\StartUp\10020115_Win_S_MessageWLAN.ps1"
$MessageScriptSource = Join-Path $Source $MessageScriptRelative
$MessageScriptDestination = Join-Path $Destination $MessageScriptRelative

# WatchDog / Skriptpfade
$ScriptRoot = Join-Path $Destination "Software\Scripte"
$ExcludedFolders = @("StartUp", "Ausfuehrung")

Write-Log -Level INFO -Message "Prüfe Internetverbindung vor Kopiervorgang..."

# ---------------------------------------------------------
# 1. IMPORT-SCHRITT (nur wenn Internet vorhanden)
# ---------------------------------------------------------
if (-not (Test-InternetConnection -Retries 5 -DelaySeconds 10 -TimeoutSec 10)) {
    Write-Log -Level "ERROR" -Message "Abbruch: Keine Internetverbindung. Versuche Message-Script auszuführen."

    $MessageScript = @($MessageScriptSource, $MessageScriptDestination) |
        Where-Object { Test-Path -Path $_ } |
        Select-Object -First 1

    if ($MessageScript) {
        Write-Log -Level "INFO" -Message "Führe Message-Script aus: $MessageScript"
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MessageScript
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Level "INFO" -Message "Message-Script ausgeführt: $MessageScript"
            } else {
                Write-Log -Level "WARN" -Message "Message-Script beendet mit Exit-Code ${LASTEXITCODE}: $MessageScript"
            }
        } catch {
            Write-Log -Level "WARN" -Message "Ausführen des Message-Scripts fehlgeschlagen: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log -Level "WARN" -Message "Message-Script nicht gefunden (Quelle: $MessageScriptSource, Ziel: $MessageScriptDestination)."
    }

    Write-Log -Level INFO -Message "Gesamter Prozess beendet."
    exit 1
}

Write-Log -Level INFO -Message "Internetverbindung vorhanden. Starte Kopiervorgang fuer Win11_C"
Write-Log -Level INFO -Message "Quelle: $Source"
Write-Log -Level INFO -Message "Ziel: $Destination"

# Entferne mögliche Offline-Attribute aus Quelldateien (robust)
Write-Log -Level INFO -Message "Entferne moegliche Offline-Attribute aus Quelldateien..."
try {
    if (Test-Path -Path $Source) {
        Get-ChildItem -Path $Source -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $item = Get-Item -LiteralPath $_.FullName -Force
                if ($item.Attributes -band [System.IO.FileAttributes]::Offline) {
                    $item.Attributes = $item.Attributes -bxor [System.IO.FileAttributes]::Offline
                }
            } catch {
                Write-Log -Level "WARN" -Message "Attrib entfernen fehlgeschlagen: $($_.FullName) - $($_.Exception.Message)"
            }
        }
    } else {
        Write-Log -Level "ERROR" -Message "Quellpfad existiert nicht: $Source"
        Write-Log -Level INFO -Message "Gesamter Prozess beendet."
        exit 1
    }
} catch {
    Write-Log -Level "WARN" -Message "Fehler beim Entfernen von Attributen: $($_.Exception.Message)"
}

# Lösche vorhandenen Zielordner falls vorhanden
if (Test-Path -Path $Destination) {
    Write-Log -Level INFO -Message "Loesche vorhandenen Ordner Win11_C..."
    try {
        Remove-Item -Path $Destination -Recurse -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
    } catch {
        Write-Log -Level "ERROR" -Message "Loeschen des Zielordners fehlgeschlagen: $($_.Exception.Message)"
        Write-Log -Level INFO -Message "Gesamter Prozess beendet."
        exit 1
    }
} else {
    Write-Log -Level INFO -Message "Ordner Win11_C existiert nicht, kein Loeschen notwendig."
}

# Erstelle Zielordner
Write-Log -Level INFO -Message "Erstelle Zielordner Win11_C..."
try {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
} catch {
    Write-Log -Level "ERROR" -Message "Erstellen des Zielordners fehlgeschlagen: $($_.Exception.Message)"
    Write-Log -Level INFO -Message "Gesamter Prozess beendet."
    exit 1
}

# Kopiere Dateien
Write-Log -Level INFO -Message "Kopiere Dateien nach Win11_C..."
try {
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force -ErrorAction Stop
    Write-Log -Level INFO -Message "Kopiervorgang abgeschlossen."
} catch {
    Write-Log -Level "ERROR" -Message "Kopiervorgang fehlgeschlagen: $($_.Exception.Message)"
    Write-Log -Level INFO -Message "Gesamter Prozess beendet."
    exit 1
}

# Entferne versteckte / system / read-only Attribute im Ziel (setze Normal)
Write-Log -Level INFO -Message "Entferne versteckte Attribute im Ziel..."
try {
    Get-ChildItem -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $it = Get-Item -LiteralPath $_.FullName -Force
            $it.Attributes = 'Normal'
        } catch {
            Write-Log -Level "WARN" -Message "Attribute setzen fehlgeschlagen: $($_.FullName) - $($_.Exception.Message)"
        }
    }
    try {
        (Get-Item -LiteralPath $Destination -Force).Attributes = 'Normal'
    } catch {
        Write-Log -Level "DEBUG" -Message "Attribute des Zielordners nicht gesetzt: $($_.Exception.Message)"
    }
} catch {
    Write-Log -Level "WARN" -Message "Fehler beim Entfernen von Attributen im Ziel: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# 2. WARTEN (3 Sekunden)
# ---------------------------------------------------------
Write-Log -Level INFO -Message "Warte 3 Sekunden, bevor WatchDog startet..."
Start-Sleep -Seconds 3

# ---------------------------------------------------------
# 3. WATCHDOG – Kodierung sicherstellen, Backup, Skripte rekursiv ausführen
# - Ignoriere Skripte direkt in Software\Scripte und in StartUp\ und Ausfuehrung\
# ---------------------------------------------------------
Write-Log -Level INFO -Message "WatchDog gestartet."
Write-Log -Level INFO -Message "Suche nach Skripten in: $ScriptRoot"
Write-Log -Level DEBUG -Message "Ausgeschlossen: Wurzelordner und $($ExcludedFolders -join ', ')"

# 1) Sicherstellen: alle Skripte konvertieren und Backup anlegen
try {
    if (Test-Path -Path $ScriptRoot) {
        Ensure-AllScriptsEncoding -RootPath $ScriptRoot
    } else {
        Write-Log -Level "WARN" -Message "ScriptRoot existiert nicht: $ScriptRoot"
    }
} catch {
    Write-Log -Level "ERROR" -Message "Fehler in Ensure-AllScriptsEncoding: $($_.Exception.Message)"
}

# 2) Skripte ausführen (separate Prozesse für Isolation; Kodierung ist jetzt kompatibel)
$Scripts = @()
if (Test-Path -Path $ScriptRoot) {
    $Scripts = @(Get-AutoRunScript -ScriptRoot $ScriptRoot -ExcludedFolder $ExcludedFolders)
} else {
    Write-Log -Level "WARN" -Message "ScriptRoot existiert nicht: $ScriptRoot"
}

if ($Scripts.Count -gt 0) {
    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    foreach ($Script in $Scripts) {
        Write-Log -Level "INFO" -Message "Starte Script (separate process): $($Script.FullName)"
        try {
            $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$($Script.FullName)`"")
            $process = Start-Process -FilePath $psExe -ArgumentList $argList -Wait -NoNewWindow -PassThru -ErrorAction Stop
            if ($process.ExitCode -eq 0) {
                Write-Log -Level "INFO" -Message "Fertig: $($Script.Name)"
            } else {
                Write-Log -Level "ERROR" -Message "Fehler in $($Script.Name): Exit-Code $($process.ExitCode)"
            }
        }
        catch {
            Write-Log -Level "ERROR" -Message "Fehler in $($Script.Name): $($_.Exception.Message)"
        }
    }
} else {
    Write-Log -Level "WARN" -Message "Keine Skripte gefunden (nach Ausschluss von Wurzelordner, $($ExcludedFolders -join ', '))."
}

Write-Log -Level INFO -Message "WatchDog abgeschlossen."
Write-Log -Level INFO -Message "Gesamter Prozess beendet."
