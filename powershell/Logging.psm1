# Globale Variablen
$script:LogFilePath = $null
$script:LogLevel = "INFO"
$script:EnableConsoleOutput = $true
$script:MaxLogSizeMB = 5
$script:DefaultLogFolder = "C:\Users\Public\10020115_WinScripts\Logs"
$script:LastLogScriptName = $null

function Initialize-Logger {
    param(
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level = "INFO",

        [bool]$ConsoleOutput = $true,

        [int]$MaxSizeMB = 5,

        # Optionaler expliziter Dateiname (z.B. für Update-Skript)
        [string]$FileName = ""
    )

    if (-not (Test-Path $script:DefaultLogFolder)) {
        New-Item -Path $script:DefaultLogFolder -ItemType Directory -Force | Out-Null
    }

    if ($FileName -ne "") {
        $Path = Join-Path $script:DefaultLogFolder $FileName
    } else {
        $date = Get-Date -Format "yyyy-MM-dd"
        $Path = Join-Path $script:DefaultLogFolder "log_$date.log"
    }

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    $script:LogFilePath        = $Path
    $script:LogLevel           = $Level
    $script:EnableConsoleOutput = $ConsoleOutput
    $script:MaxLogSizeMB       = $MaxSizeMB
    $script:LastLogScriptName  = $null

    Write-Log -Level "INFO" -Message "Logger initialisiert. Logfile: $Path"
}

function Invoke-LogRotation {
    if (-not $script:LogFilePath -or -not (Test-Path $script:LogFilePath)) { return }

    $sizeMB = (Get-Item $script:LogFilePath).Length / 1MB
    if ($sizeMB -ge $script:MaxLogSizeMB) {
        $timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
        $archivePath = "$script:LogFilePath.$timestamp.bak"
        Move-Item -Path $script:LogFilePath -Destination $archivePath -Force
        New-Item  -Path $script:LogFilePath -ItemType File -Force | Out-Null
    }

    # Tagesrotation nur bei tagesbasiertem Dateinamen
    if ($script:LogFilePath -match "log_\d{4}-\d{2}-\d{2}\.log$") {
        $currentDate  = Get-Date -Format "yyyy-MM-dd"
        $expectedFile = Join-Path $script:DefaultLogFolder "log_$currentDate.log"
        if ($expectedFile -ne $script:LogFilePath) {
            $script:LogFilePath = $expectedFile
            if (-not (Test-Path $expectedFile)) {
                New-Item -Path $expectedFile -ItemType File -Force | Out-Null
            }
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $script:LogFilePath) {
        Initialize-Logger
    }

    $levels = @{ DEBUG = 1; INFO = 2; WARN = 3; ERROR = 4 }
    if ($levels[$Level] -lt $levels[$script:LogLevel]) { return }

    Invoke-LogRotation

    $callStack   = Get-PSCallStack
    $scriptFrame = $callStack | Where-Object { $_.ScriptName -and $_.ScriptName.Trim() -ne "" } | Select-Object -First 1
    $scriptName  = if ($scriptFrame) {
        Split-Path $scriptFrame.ScriptName -Leaf
    } elseif ($PSCommandPath) {
        Split-Path $PSCommandPath -Leaf
    } else {
        $Host.Name
    }

    if ($script:LastLogScriptName -ne $scriptName) {
        $nl         = [Environment]::NewLine
        $headerText = "$nl$nl$nl+++ $scriptName +++"
        Add-Content -Path $script:LogFilePath -Value $headerText
        if ($script:EnableConsoleOutput) {
            Write-Host $headerText -ForegroundColor Magenta
        }
        $script:LastLogScriptName = $scriptName
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[$timestamp] [$Level] $Message"

    Add-Content -Path $script:LogFilePath -Value $entry

    if ($script:EnableConsoleOutput) {
        switch ($Level) {
            "ERROR" { Write-Host $entry -ForegroundColor Red }
            "WARN"  { Write-Host $entry -ForegroundColor Yellow }
            "INFO"  { Write-Host $entry -ForegroundColor Cyan }
            "DEBUG" { Write-Host $entry -ForegroundColor DarkGray }
        }
    }
}

function Get-LogConfig {
    [PSCustomObject]@{
        LogFilePath    = $script:LogFilePath
        LogLevel       = $script:LogLevel
        ConsoleOutput  = $script:EnableConsoleOutput
        MaxLogSizeMB   = $script:MaxLogSizeMB
        DefaultFolder  = $script:DefaultLogFolder
        LastScriptName = $script:LastLogScriptName
    }
}

function Close-Logger {
    if ($script:LogFilePath) {
        Write-Log -Level "INFO" -Message "Logger wird geschlossen."
    }
    $script:LogFilePath       = $null
    $script:LastLogScriptName = $null
}

Export-ModuleMember -Function Initialize-Logger, Write-Log, Invoke-LogRotation, Get-LogConfig, Close-Logger
