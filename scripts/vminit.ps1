# VMWare Provisioning Script
#
# 1) Runs sysprep to initialize new SID
#
# 2) Applies settings for network found in ovf.
#
# 3) This assumes ovf has the following section is defined in the Guest's OVF file:
#
# <ProductSection ovf:class="vami" ovf:instance="windows_server_2019">
#   <Info>VAMI Properties</Info>
#   <Category>Network Properties</Category>
#   <Property ovf:key="hostname" ovf:type="string" ovf:userConfigurable="true">
#     <Label>Host Name</Label>
#     <Description>Leave blank if DHCP is desired.</Description>
#   </Property>
#   <Property ovf:key="ip0" ovf:type="string" ovf:userConfigurable="true">
#     <Label>IP Address</Label>
#     <Description>The IP address for this interface. Leave blank if DHCP is desired.</Description>
#   </Property>
#   <Property ovf:key="netmask0" ovf:type="string" ovf:userConfigurable="true">
#     <Label>Netmask</Label>
#     <Description>The netmask or prefix for this interface. Leave blank if DHCP is desired.</Description>
#   </Property>
#   <Property ovf:key="gateway" ovf:type="string" ovf:userConfigurable="true">
#     <Label>Default Gateway</Label>
#     <Description>The default gateway address for this VM. Leave blank if DHCP is desired.</Description>
#   </Property>
#   <Property ovf:key="dns" ovf:type="string" ovf:userConfigurable="true">
#     <Label>DNS Servers</Label>
#     <Description>The domain name servers for this VM (comma separated). Leave blank if DHCP is desired.</Description>
#   </Property>
#   <Property ovf:key="domain" ovf:type="string" ovf:userConfigurable="true">
#     <Label>Domain Name</Label>
#     <Description>The domain name of this VM. Leave blank if DHCP is desired.</Description>
#   </Property>
#   <Property ovf:key="searchpath" ovf:type="string" ovf:userConfigurable="true">
#     <Label>Domain Search Path</Label>
#     <Description>The domain search path (comma separated domain names) for this VM. Leave blank if DHCP is desired.</Description>
#   </Property>
# </ProductSection>
#
# 4) XML Structure of $vmenvxml:
#
# <?xml version="1.0" encoding="UTF-8"?>
# <Environment xmlns="http://schemas.dmtf.org/ovf/environment/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:oe="http://schemas.dmtf.org/ovf/environment/1" xmlns:ve="http://www.vmware.c
# om/schema/ovfenv" oe:id="" ve:esxId="52">
#   <PlatformSection>
#     <Kind>VMware ESXi</Kind>
#     <Version>6.7.0</Version>
#     <Vendor>VMware, Inc.</Vendor>
#     <Locale>US</Locale>
#   </PlatformSection>
#   <PropertySection>
#     <Property oe:key="vami.hostname.windows_server_2019" oe:value="winsrv01.lab.local"/>
#     <Property oe:key="vami.ip0.windows_server_2019" oe:value="192.168.10.10"/>
#     <Property oe:key="vami.netmask0.windows_server_2019" oe:value="255.255.255.0"/>
#     <Property oe:key="vami.gateway.windows_server_2019" oe:value="192.168.10.1"/>
#     <Property oe:key="vami.dns.windows_server_2019" oe:value="8.8.8.8,8.4.4.4"/>
#     <Property oe:key="vami.domain.windows_server_2019" oe:value="lab.local"/>
#     <Property oe:key="vami.searchpath.windows_server_2019" oe:value="lab.local"/>
#   </PropertySection>
# </Environment>
#
# 5) Schedule this script to run at boot
#
# schtasks /create /tn "VmInit" /sc onstart /rl highest /ru SYSTEM /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'c:\path\to\vminit.ps1'"

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$vminitFolder = "c:\__provision__"

# location to save vmenv.xml
$vmenvxml = "$vminitFolder\vmenv.xml"

# location of initial sysprep file
$sysprepfile = "$vminitFolder\sysprep.xml"

# file that flags sysprep has ran
$sysprepflagStarted = "$vminitFolder\__sysprep-started__"
$sysprepflagComplete = "$vminitFolder\__sysprep-complete__"

# get network interface name
$ifname = Get-NetAdapter | Select -expand Name

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

# function to convert a subnetmask (ie 255.255.255.0) to a netmask prefix (ie 24)
function Convert-IpAddressToMaskLength([string] $dottedIpAddressString) {
  $result = 0

  # ensure we have a valid IP address
  [IPAddress]$ip = $dottedIpAddressString
  $octets = $ip.IPAddressToString.Split('.')
  foreach($octet in $octets) {
    while(0 -ne $octet) {
      $octet = ($octet -shl 1) -band [byte]::MaxValue
      $result++
    }
  }
  return $result
}

function Touch-File($filepath) {
  if (!(Test-Path $filepath -PathType Leaf)) {
    New-Item -ItemType file $filepath
  }

  (gci $filepath).LastWriteTime = Get-Date
}

function Reset-Network() {
  try {
    Get-NetIPAddress -InterfaceAlias "$ifname" -AddressFamily IPv4 | Remove-NetRoute -Confirm:$false
  } catch {
    Write-Host $_
  }

  Set-NetIPInterface -InterfaceAlias "$ifname" -Dhcp Enabled
  Set-DnsClientServerAddress -InterfaceAlias $ifname -ResetServerAddresses

  Restart-NetAdapter -Name "$ifname" -Confirm:$false
}

function Refresh-VmEnvXml($filepath) {
  # remove existing file
  if(Test-Path $filepath -PathType Leaf) {
    Remove-Item $filepath
  }

  # query vmtoolsd for ovf properties and write to file
  $vmtoolsdCmd = "c:\Program Files\VMware\VMware Tools\vmtoolsd.exe"
  $vmtoolsdArgs = "--cmd=`"info-get guestinfo.ovfEnv`""
  $process = Start-Process -FilePath "$vmtoolsdCmd" -ArgumentList $vmtoolsdArgs -Wait -PassThru -RedirectStandardOutput "$filepath"
  $exit_code = $process.ExitCode

  if ($exit_code -ne 0) {
    throw "Failed to query VMTools: exit code $exit_code"
  }
}

function Run-Sysprep() {
  $sysprepCmd = "c:\windows\system32\sysprep\sysprep.exe"
  $sysprepArgs = "/generalize /reboot /oobe /mode:vm /unattend:`"$sysprepfile`""

  # run sysprep
  $process = Start-Process -FilePath "$sysprepCmd" -ArgumentList $sysprepArgs -Wait -PassThru
  $exit_code = $process.ExitCode

  if ($exit_code -ne 0) {
    throw "Failed to run sysprep: exit code $exit_code"
  }
}

function Config-Network($filepath) {
  # flag if reboot is required at end of script
  $rebootRequired = $False

  # Parse XML and collect variables
  [xml]$vmenv = Get-Content "$filepath"
  [IPAddress]$vmIP = $vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.ip0*' } | select -expand value
  [string]$vmNetmask = $vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.netmask0*' } | select -expand value
  [IPAddress]$vmGW = $vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.gateway*' } | select -expand value
  [string]$vmHostname = $vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.hostname*' } | select -expand value
  [IPAddress[]]$vmDNS = ($vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.dns*' } | select -expand value).replace("\s", "").split(',')
  [string]$vmDomain = $vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.domain*' } | select -expand value
  [string[]]$vmSearchpath = ($vmenv.Environment.PropertySection.Property | ?{ $_.key -like '*vami.searchpath*' } | select -expand value).replace("\s", "").split(',')
  [byte]$vmPrefix = 0

  # get current host config
  [string]$currentIP = Get-NetIPAddress -InterfaceAlias $ifname -AddressFamily IPv4 | select -expand "IPAddress"
  [string]$currentPrefix = Get-NetIPAddress -InterfaceAlias $ifname -AddressFamily IPv4 | select -expand "PrefixLength"
  [string]$currentGW = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | select -expand "NextHop"
  [string]$currentHostname = $Env:Computername

  # if ovf properties are present
  if ($vmIP -And $vmNetmask -And $vmGW) {
    # convert subnet mask to subnet prefix
    try {
      $vmPrefix = [byte]$vmNetmask
    } catch {
      [IPAddress]$vmNetmask = $vmNetmask
      $vmPrefix = Convert-IpAddressToMaskLength -dottedIpAddressString $vmNetmask.IPAddressToString
    }
    if ($vmPrefix -gt 32 -Or $vmPrefix -lt 0) {
      throw "Invalid subnetmask / prefix found in ovf properties..."
    }

    # test ovf network properties are set
    if ($vmIP -And $vmPrefix -And $vmGW) {
      # test if network needs to be updated
      if ($currentIP -ne $vmIP.IPAddressToString -Or $currentPrefix -ne $vmPrefix -Or $currentGW -ne $vmGW.IPAddressToString) {
        # configure new network interface
        New-NetIPAddress -InterfaceAlias $ifname -IPAddress $vmIP.IPAddressToString -PrefixLength $vmPrefix -DefaultGateway $vmGW.IPAddressToString

        # toggle flag to reboot
        $rebootRequired = $True
      }
    }

    # test if ovf host name is set
    if ($vmHostname) {
      # test if hostname needs to be updated
      if ($vmHostname.ToLower() -ne $currentHostname.ToLower()) {
        Rename-Computer -NewName "$vmHostname" -Force -Restart:$False

        # toggle flag to reboot
        $rebootRequired = $True
      }
    }

    # test if ovf dns is set
    if ($vmDNS) {
      # set dns servers
      Set-DnsClientServerAddress -InterfaceAlias $ifname -ServerAddresses $vmDNS
    }

    # test if ovf domain is set
    if ($vmDomain) {
      Set-DnsClient -InterfaceAlias $ifname -ConnectionSpecificSuffix "$vmDomain"
    }

    # test if ovf searchpath is set
    if ($vmSearchpath) {
      Set-DnsClientGlobalSetting -SuffixSearchList $vmSearchpath
    }
  }

  return $rebootRequired
}

# update ovf properties and configure network
try {
  # wait for vmtools service to start
  Wait-Service -serviceName "vmtools" -timeoutSeconds 60

  # check if sysprep has started, if not start sysprep
  if(!(Test-Path $sysprepflagStarted -PathType Leaf)) {
    Touch-File -filepath "$sysprepflagStarted"

    # perform sysprep
    Run-Sysprep
  }

  # check if sysprep has completed, if so apply network config
  if(Test-Path $sysprepflagComplete -PathType Leaf) {
    # refresh vmenv.xml
    Refresh-VmEnvXml -filepath "$vmenvxml"

    # configure network
    $reboot = Config-Network -filepath "$vmenvxml"

    # reboot if required to apply ovf properties
    if ($reboot) {
      shutdown /r /f /t 10 /d p:4:1 /c "Restarting for Network reconfiguration by VmInit..."
    }
  }
} catch {
  Write-Error -Message "$_"
}
