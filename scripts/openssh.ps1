$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

Write-Host "Adding Windows Capability for OpenSSH Server and Client..."

# Add SSH Client and Server
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Set Services to automatic
Set-Service -Name sshd -StartupType 'Automatic'
