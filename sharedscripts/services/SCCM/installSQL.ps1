# ==============================================================================
# Script: Install-SQL_Combined.ps1
# Purpose: Unified SQL Install - Offline preferred, auto-downloads ISO if needed
# ==============================================================================

$ErrorActionPreference = "Stop"

# Import Phase Timer Module
Import-Module "$PSScriptRoot\PhaseTimer.psm1" -Force

# --- CONFIGURATION ---
$LocalSource = "C:\vagrant\sharedscripts\services\SCCM\SQL-offline"
$LocalISO = "C:\Windows\Temp\SQLServer2019.iso" # Define a local path (The "Safe" Zone)
$WebInstaller = "C:\Windows\Temp\SQL2019-SSEI-Dev.exe"
$DownloadTarget = "C:\vagrant\sharedscripts\services\SCCM\SQL-offline" 
$InstanceName = "MSSQLSERVER"
$Collation = "SQL_Latin1_General_CP1_CI_AS"

# --- STEP 1: PREPARE INSTALLER ---
Start-PhaseTimer -PhaseName "PREPARING SQL INSTALLER"
$SetupExe = "$LocalSource\setup.exe"
$InstallCommand = ""

# PREREQUISITES
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ((Get-Service "BITS").Status -ne "Running") {
    Set-Service -Name BITS -StartupType Manual
    Start-Service -Name BITS
}
if (-not (Test-Path $DownloadTarget)) { New-Item -Path $DownloadTarget -ItemType Directory | Out-Null }

# 1. Check for EXTRACTED media (setup.exe)
if (Test-Path $SetupExe) {
    Write-Host " [MODE] Local Offline Media Found (Extracted)." -ForegroundColor Green
    $InstallCommand = $SetupExe
}
else {
    # 2. Check for ISO media (The missing check!)
    $ISO = Get-ChildItem -Path $DownloadTarget -Filter "*.iso" | Select-Object -First 1

    if ($ISO) {
        Write-Host " [MODE] Existing ISO Found: $($ISO.Name)" -ForegroundColor Green
    }
    else {
        # 3. Neither found, trigger DOWNLOAD
        Write-Host " [MODE] No Media Found. Downloading ISO..." -ForegroundColor Yellow
        
        if (-not (Test-Path $WebInstaller)) {
            Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=866662" -OutFile $WebInstaller -UseBasicParsing
        }
        Unblock-File -Path $WebInstaller -ErrorAction SilentlyContinue

        $DownloadArgs = @("/Action=Download", "/MediaType=ISO", "/MediaPath=`"$DownloadTarget`"", "/Quiet")
        $DLProcess = Start-Process -FilePath $WebInstaller -ArgumentList $DownloadArgs -Wait -PassThru

        if ($DLProcess.ExitCode -ne 0) {
            Write-Error " [FAIL] Download failed (Code: $($DLProcess.ExitCode))."
            exit 1
        }
        
        # Refresh variable after download
        $ISO = Get-ChildItem -Path $DownloadTarget -Filter "*.iso" | Select-Object -First 1
        if (-not $ISO) { Write-Error " [FAIL] Download finished but ISO is missing."; exit 1 }
    }



    # 4. Common Mount Logic (Runs for both Existing and Downloaded ISOs)
    # 3. Copy the file (Required!)
    Write-Host "Copying ISO to local drive ..."
    Copy-Item -Path $ISO.FullName -Destination $LocalISO -Force
    Write-Host "   Mounting ISO..." -ForegroundColor Cyan
    $MountResult = Mount-DiskImage -ImagePath $LocalISO -PassThru
    $DriveLetter = ($MountResult | Get-Volume).DriveLetter
    
    if (-not $DriveLetter) {
        Write-Error " [FAIL] Failed to mount ISO."
        exit 1
    }

    $InstallCommand = "$($DriveLetter):\setup.exe"
    Write-Host " [OK] Media Mounted on $($DriveLetter):\" -ForegroundColor Green
}
Stop-PhaseTimer -Status Success


# --- STEP 2: INSTALLATION --- (rest unchanged from original)
Start-PhaseTimer -PhaseName "INSTALLING SQL SERVER"

if (Get-Service $InstanceName -ErrorAction SilentlyContinue) {
    Write-Host "[SKIP] SQL Server is already installed." -ForegroundColor Green
    Stop-PhaseTimer -Status Success
}
else {
    Write-Host "Starting Installer in Background..." 

    $Arguments = @(
        "/Q", "/ACTION=Install", "/IACCEPTSQLSERVERLICENSETERMS",
        "/FEATURES=SQLEngine", "/INSTANCENAME=$InstanceName",
        "/SQLSVCACCOUNT=`"NT AUTHORITY\SYSTEM`"",   
        "/SQLSYSADMINACCOUNTS=`"BUILTIN\ADMINISTRATORS`"",
        "/AGTSVCACCOUNT=`"NT AUTHORITY\SYSTEM`"",
        "/SQLCOLLATION=$Collation", "/TCPENABLED=1", "/NPENABLED=1", "/UpdateEnabled=0"
    )

    # 1. Start the Installer (record start time for log correlation)
    $StartTime = Get-Date
    $Process = Start-Process -FilePath $InstallCommand -ArgumentList $Arguments -PassThru
    


    # 2. Locate and Announce Log File
    Start-Sleep -Seconds 10 
    $LogFolder = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "Log" -and $_.CreationTime -ge $StartTime.AddSeconds(-30) } |
    ForEach-Object {
        Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue
    } |
    Where-Object { Test-Path (Join-Path $_.FullName "Summary.txt") } |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1

    if ($LogFolder) {
        $LogPath = Join-Path $LogFolder.FullName "Summary.txt"
        Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host " [INFO] LOG FILE LOCATION:" -ForegroundColor Yellow
        Write-Host " $LogPath"
        Write-Host " To watch live, run: Get-Content `"$LogPath`" -Wait -Tail 10" -ForegroundColor Gray
        Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
    }

    # 3. Progress Loop (Simple Timer)
    while (-not $Process.HasExited) {
        $Elapsed = New-TimeSpan -Start $StartTime -End (Get-Date)
        $msg = "`r    Installing... [Time Elapsed: {0:mm}m {0:ss}s] " -f $Elapsed
        Write-Host -NoNewline $msg
        Start-Sleep -Seconds 10
    }

    Write-Host "" 

    # 4. Check Exit Code
    if ($Process.ExitCode -eq 0) {
        Write-Host " [OK] Installation Completed (Exit Code 0)." -ForegroundColor Green
        Stop-PhaseTimer -Status Success
    }
    elseif ($Process.ExitCode -eq 3010) {
        Write-Host " [WARN] Installation Complete (Reboot Required)." -ForegroundColor Yellow
        Stop-PhaseTimer -Status Warning
    }
    else {
        Stop-PhaseTimer -Status Failed
        Write-Error " [FAIL] Install Failed (Code: $($Process.ExitCode)). Check Log: $LogPath"
        exit 1
    }
}

# --- STEP 3: POST-CONFIGURATION ---
Start-PhaseTimer -PhaseName "SQL SERVER CONFIGURATION"

# Force Start Service
$MaxRetries = 5
for ($i = 0; $i -lt $MaxRetries; $i++) {
    if ((Get-Service $InstanceName -ErrorAction SilentlyContinue).Status -eq 'Running') { break }
    Start-Service $InstanceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

# Firewall
if (-not (Get-NetFirewallRule -DisplayName "SQL Server 1433" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "SQL Server 1433" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
}

# --- FINAL VERIFICATION ---
Write-Host "`n--- FINAL VERIFICATION ---" -ForegroundColor Magenta
$Service = Get-Service $InstanceName -ErrorAction SilentlyContinue

if ($Service.Status -eq "Running") {
    Write-Host "[OK] Service $InstanceName is Running." -ForegroundColor Green
}
else {
    Write-Error "[FAIL] Service $InstanceName is $($Service.Status)."
    exit 1
}

$Port = Get-NetTCPConnection -LocalPort 1433 -State Listen -ErrorAction SilentlyContinue
if ($Port) {
    Write-Host "[OK] Port 1433 is Listening." -ForegroundColor Green
}

# Dismount ISO after starting (no longer needed)
Dismount-DiskImage -ImagePath $LocalISO

Stop-PhaseTimer -Status Success

# Show installation summary
Show-InstallationSummary

