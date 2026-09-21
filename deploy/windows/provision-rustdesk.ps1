<#
.SYNOPSIS
    Silently installs RustDesk as a service and configures it for unattended,
    popup-free access: permanent password, password-only approval (no
    accept/reject dialog), and the connection-manager window hidden (no
    focus-stealing popup on connect).

.PARAMETER InstallerPath
    Path to the RustDesk installer executable (the built .exe, not the
    already-installed copy).

.PARAMETER PermanentPassword
    The permanent password to set for unattended access. Every machine
    provisioned with this script will accept this password.

.NOTES
    Must be run elevated (as Administrator) — RustDesk's --password and
    --option CLI commands require admin rights against the installed,
    running service.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$PermanentPassword
)

$ErrorActionPreference = "Stop"

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator."
}

if (-not (Test-Path $InstallerPath)) {
    throw "Installer not found at: $InstallerPath"
}

$installedExe = Join-Path $env:ProgramFiles "RustDesk\RustDesk.exe"

Write-Host "Installing RustDesk silently as a service..."
Start-Process -FilePath $InstallerPath -ArgumentList "--silent-install" -Wait

$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-Path $installedExe)) {
    if ((Get-Date) -gt $deadline) {
        throw "RustDesk did not finish installing within 60 seconds (expected at $installedExe)."
    }
    Start-Sleep -Seconds 1
}

# The service was just started by the installer (`sc start`); give its IPC
# pipe a moment to come up before the CLI commands below try to reach it.
Start-Sleep -Seconds 5

Write-Host "Setting permanent password..."
$passwordResult = & $installedExe --password $PermanentPassword
Write-Host "  -> $passwordResult"
if ($passwordResult -notmatch "Done!") {
    throw "Failed to set permanent password: $passwordResult"
}

Write-Host "Configuring silent unattended access (no approval dialog, no connection-manager popup)..."
& $installedExe --option verification-method use-permanent-password
& $installedExe --option approve-mode password
& $installedExe --option allow-hide-cm Y

Write-Host "Done. RustDesk is installed, running as a service, and will accept connections with the configured password with no on-screen prompts."
