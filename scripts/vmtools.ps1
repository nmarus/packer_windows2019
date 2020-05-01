# Installs VM Tools on host by downloading it from packages.vmware.com
# and the running the installer.
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

# Drivers: Drivers,AppDefense,Audio,BootCamp,Buslogic,Debug,FileIntrospection,
#          Hgfs,LSI,MemCtl,Mouse,MouseUsb,NetworkIntrospection,PVSCSI,SVGA,Sync,
#          TrayIcon,VMCI,VMXNet,VMXNet3,VSS
# Toolbox: Toolbox,Unity,PerfMon
$vmtools_components_add = "ALL"
$vmtools_components_remove = "Audio,Hgfs"

$tools_version = "10.3.10"
$tools_patch = "12406962"
$file_name = "VMware-tools-$tools_version-$tools_patch-x86_64.exe"
$download_url = "https://packages.vmware.com/tools/releases/$tools_version/windows/x64/$file_name"
$download_dir = "c:\__provision__\installs"
$vmtoolsCmd = "$download_dir\$file_name"
$vmtoolsArgs = "/S /v `"/qn /l*v `"$download_dir\vmware_tools.log`" REBOOT=R ADDLOCAL=$vmtools_components_add REMOVE=$vmtools_components_remove`""

# wait for a service to start
function Wait-Service([string]$serviceName, [int32]$timeoutSeconds) {
  $timeSpan = New-Object Timespan 0,0,$timeoutSeconds
  $service = Get-Service $serviceName
  $running = $False

  if (-not $service) {
    [int32]$retrySeconds = 5
    [int32]$remainingSeconds = $timeoutSeconds - $retrySeconds

    if ($remainingSeconds -gt $retrySeconds) {
      Write-Host "Service not found ${serviceName}! Trying again in $retrySeconds seconds..."
      Start-Sleep -Seconds $retrySeconds
      return Wait-Service -serviceName "$serviceName" -timeoutSeconds $remainingSeconds
    }

    if ($remainingSeconds -gt 0) {
      Start-Sleep -Seconds 1
      return Wait-Service -serviceName "$serviceName" -timeoutSeconds $remainingSeconds
    }

    throw "Timed out waiting for the service $serviceName to be found..."
  }

  # check if service is already running
  $running = $service.Status -eq [ServiceProcess.ServiceControllerStatus]::Running

  # if not running, wait for service to start
  if (-not $running) {
    $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, $timeSpan)
  }
}

Function Run-Process($executable, $arguments) {
  $process = New-Object -TypeName System.Diagnostics.Process
  $psi = $process.StartInfo
  $psi.FileName = $executable
  $psi.Arguments = $arguments
  Write-Verbose -Message "starting new process '$executable $arguments'"
  $process.Start() | Out-Null

  $process.WaitForExit() | Out-Null
  $exit_code = $process.ExitCode
  Write-Verbose -Message "process completed with exit code '$exit_code'"

  return $exit_code
}

try {
  # check if file exists, if not, download
  if(!(Test-Path "$vmtoolsCmd" -PathType Leaf)) {

    # check if download dir exists, if not, create
    if(!(Test-Path "$download_dir" -PathType Container)) {
      New-Item "$download_dir" -ItemType Directory
    }

    # download vmtools installer
    Write-Host "Downloading from $download_url to $vmtoolsCmd"
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($download_url,$vmtoolsCmd)
  }

  # run vmtools installer
  Write-Host "Start installing VMware tools..."
  $exit_code = Run-Process -executable "$vmtoolsCmd" -arguments "$vmtoolsArgs"

  if ($exit_code -eq 3010 -Or $exit_code -eq 0) {
    # wait for vmtools service to start
    Write-Host "Waiting up to 5m for vmtools service to start..."
    Wait-Service -serviceName "vmtools" -timeoutSeconds 300

    Write-Host "Install of VMTools complete!"
  } else {
    Write-Error -Message "Failed to install VMTools: exit code $exit_code"
  }
} catch {
  Write-Error -Message "$_"
}
