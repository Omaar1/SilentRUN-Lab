# --- CONFIGURATION ---
# --- CONFIGURATION VARIABLES ---
$SiteCode = "PS1"
$SiteServer = "SCCM.silent.run"    
$User = "SILENT\sccm_cpia"
$Password = "P@ssw0rd"
# ---------------------

# ============================================================================== #
# INITIALIZATION: LOAD MODULE & CONNECT TO SITE
# ============================================================================== #
Write-Host "--- INITIALIZING SCCM MODULE ---" -ForegroundColor Cyan
try {
    # 1. Locate ConfigurationManager.psd1 via Registry
    $RegKey = "HKLM:\SOFTWARE\Microsoft\ConfigMgr10\Setup"
    $ConsolePath = $null
    
    if (Test-Path $RegKey) {
        $InstallDir = (Get-ItemProperty -Path $RegKey -Name "UI Installation Directory" -ErrorAction SilentlyContinue)."UI Installation Directory"
        if ($InstallDir) {
            $ConsolePath = Join-Path $InstallDir "bin\ConfigurationManager.psd1"
        }
    }

    # 2. Fallback: Check Standard Paths if registry lookup fails
    if (-not $ConsolePath -or -not (Test-Path $ConsolePath)) {
        $PossiblePaths = @(
            "$($Env:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1",
            "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\ConfigurationManager.psd1",
            "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1",
            "C:\Program Files\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"
        )
        $ConsolePath = $PossiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    # 3. Load the Module
    if ($ConsolePath -and (Test-Path $ConsolePath)) {
        Write-Host " [INFO] Found Module at: $ConsolePath" -ForegroundColor Gray
        Import-Module $ConsolePath -ErrorAction Stop
    }
    else {
        Throw "Could not locate ConfigurationManager.psd1 in any standard location."
    }

    # 4. Connect to Site
    if ((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer -ErrorAction Stop | Out-Null
    }
    Set-Location "$($SiteCode):"
    Write-Host " [OK] Connected to Site $SiteCode" -ForegroundColor Green

}
catch {
    Write-Error "Failed to load SCCM Module: $_"
    exit 1
}

# 1. Define the Credential (SCCM needs the password to store it locally)
$SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force
# $Cred = New-Object System.Management.Automation.PSCredential ($User, $SecurePass)

# 2. Register the AD User into SCCM's internal list of accounts
Write-Host "[*] Registering AD User '$User' into SCCM database..." -ForegroundColor Cyan
if (-not (Get-CMAccount -Name $User -ErrorAction SilentlyContinue)) {
    # This command maps the AD user to an SCCM-managed credential
    New-CMAccount -Password $SecurePass -Name $User -SiteCode $SiteCode | Out-Null
    Write-Host " [OK] AD User is now an authorized SCCM Account." -ForegroundColor Green
}

# 5. Apply Settings (Using your exact parameters)
# Note: Changed -AddAccount $User to -AddAccount $Cred so it passes the password correctly.
Set-CMClientPushInstallation `
    -SiteCode $SiteCode `
    -AllownNTLMFallback $true `
    -EnableSystemTypeServer $true `
    -EnableSystemTypeWorkstation $true `
    -EnableSystemTypeConfigurationManager $true `
    -EnableAutomaticClientPushInstallation $true `
    -AddAccount $User `
    # -Verbose