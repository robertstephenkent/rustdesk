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

.PARAMETER ServerHost
    Address of the self-hosted rendezvous/relay server (hbbs/hbbr), e.g. a
    school-controlled VPS. If omitted, the client uses RustDesk's public
    servers instead.

.PARAMETER ServerKey
    The hbbs server's public key (from its data/id_ed25519.pub), required
    alongside -ServerHost so the client trusts it.

.NOTES
    Must be run elevated (as Administrator) — RustDesk's --password and
    --option CLI commands require admin rights against the installed,
    running service.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$PermanentPassword,

    [string]$ServerHost,

    [string]$ServerKey
)

if ($ServerHost -and -not $ServerKey) {
    throw "-ServerKey is required when -ServerHost is set (the client won't trust the server without it)."
}

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

function Set-RustDeskOption {
    param([string]$Key, [string]$Value)
    # Rapid back-to-back IPC calls to the service can silently drop one, so
    # verify each option landed and retry a few times before giving up.
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        & $installedExe --option $Key $Value | Out-Null
        Start-Sleep -Milliseconds 500
        $actual = & $installedExe --option $Key
        if ($actual -eq $Value) { return }
    }
    throw "Failed to set option '$Key' to '$Value' after 5 attempts (last read back: '$actual')."
}

Write-Host "Configuring silent unattended access (no approval dialog, no connection-manager popup)..."
Set-RustDeskOption -Key "verification-method" -Value "use-permanent-password"
Set-RustDeskOption -Key "approve-mode" -Value "password"
Set-RustDeskOption -Key "allow-hide-cm" -Value "Y"

if ($ServerHost) {
    Write-Host "Pointing this client at the self-hosted server ($ServerHost)..."
    Set-RustDeskOption -Key "key" -Value $ServerKey
    Set-RustDeskOption -Key "custom-rendezvous-server" -Value $ServerHost
    Set-RustDeskOption -Key "relay-server" -Value $ServerHost
}

Write-Host "Done. RustDesk is installed, running as a service, and will accept connections with the configured password with no on-screen prompts."
