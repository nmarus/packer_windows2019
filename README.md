# Packer Windows Server 2019 OVF/OVA Builder

The intent of this builder is to create a Windows OVA from a Windows ISO fully
scripted and without any user interaction. This includes the automation to
configure network settings and enable the configuration and services to allow
ssh or win-rm based automation tools to finalize customization.

This builder is entirely programatic. This builder starts with a plain Windows
2019 ISO and customizes from there.

Features:

* **Formats:** Creates both OVF and OVA files.
* **Duplicate SID Handling:** Sysprep automatically ran on initial boot of the
  OVA deployed Virtual machine. This regenerates the Windows SID to avoid issues
  when joining to a domain.
* **OVF Deployment Options:** OVF modified to include options to allow setting
  the IP, subnet, gateway, name servers, and domain name, when deploying into
  VMware. This can be utilized by either filling in the form when importing the
  OVA or with injecting OVF properties with tools such as Ansible's
  "vmware_deploy_ovf" module or with CLI tools such as govc.
* **OVF Property Monitoring:** A script set to run on boot that checks the OVF
  properties. It will automatically apply changes on the initial boot, or when
  VApp properties have changed post-deployment.
* **Ansible compatibility:**
  * Win RM Hotfix KB2842230 applied
  * Win RM configured to allow Ansible connections
* **Remote Access:**
  * Remote Desktop Services are enabled to allow connection through Microsoft
    Windows Terminal Services Client.
  * OpenSSH Service enabled during first boot sysprep to ensure non-duplicate
    ssh host keys.

## Prerequisites for Packer Build

###  Locally Installed Utils / Apps:

Requires the following in your `<path>`:

* **Packer CLI Tool:** Packer is a image creation tool by HashiCorp that easily
  allows scripting of image builds. (v1.5.5+ is required for "vcenter"
  provisioner)
* **VMWare ovftool:** Tool from VMware that converts between various Virtual
  Machine formats.

### ISO Images:

You must downloaded the required Windows 2019 ISO image for the packer script
to work. The path to this is specified in the packer vars file (`vars.json`).
Samples for the config files are found in the project folder with the filename
suffix `_sample`.

### Config:

The following config files must be created before running.

* Image configuration can be found in file(s): `vars.json`
* Provisioner configuration can be found in file(s): `<provisioner>-config.json`
  (local does not require a provisioner).

#### Image Types:

The image type created is defined in the `autounattend.xml` file.

Known types are:

* Windows Server 2019 SERVERDATACENTER (default)
* Windows Server 2019 SERVERDATACENTERCORE
* Windows Server 2019 SERVERSTANDARD
* Windows Server 2019 SERVERSTANDARDCORE

This can be changed in the following section of the `autounattend.xml` file.
```xml
<InstallFrom>
  <MetaData wcm:action="add">
    <Key>/IMAGE/NAME</Key>
    <Value>Windows Server 2019 SERVERDATACENTER</Value>
  </MetaData>
</InstallFrom>
```

## Windows Licensing

The Windows License key can be specified in the `autounattend.xml` file. This
can be updated in the following section:

```xml
<UserData>
  <AcceptEula>true</AcceptEula>
  <ProductKey>
    <!-- <Key>11111-22222-33333-44444-55555</Key> -->
    <WillShowUI>Never</WillShowUI>
  </ProductKey>
</UserData>
```

By default the license is not defined. This causes the image to built with a
evaluation license of 180 days. This evaluation period begins when the OVA/OVF
is deployed as a VM and NOT when the OVA is initially generated.

This allows short term environments to be stood up for lab and test purposes.

To verify how much time is left on the trial, run the following commands from
powershell:

```powershell
Get-CimInstance SoftwareLicensingProduct
```

Look for `GracePeriodRemaining`. This is the number of minutes remaining.

```
[...]
GracePeriodRemaining                           : 259166
[...]
```

## OVF VApp Properties

This script modifies the OVF to include options to allow setting the IP, subnet,
gateway, name servers, and domain name when deploying into VMware. This can be
utilized by either filling in the form when importing the OVA or when using OVF
properties of tools such as the Ansible "vmware_deploy_ovf" module or the GOVC
command line tool. (see examples at end)

This allows the Hypervisor to include a form to configure network properties
when deploying the OVF/OVA.

#### VApp properties on VMware Fusion on OSX

![vmware fusion](/images/ovf-properties-fusion.jpg)

### VApp properties VMware ESXi 6.x

![vmware exsi](/images/ovf-properties-esxi.jpg)

### Modifying the VApp Properties After Deployment

If this OVF/OVA is deployed to a VMWare VCenter managed environment, it is
[possible](https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.vsphere.vm_admin.doc/GUID-D0F9E3B9-B77B-4DEF-A982-49B9F6358FF3.html)
to change the VApp properties of the Virtual Machine after it has been deployed.

When this happens, this will be seen by the Virtual Machine on its next reboot.
Once it sees a change, it will apply it and automatically reboot. Changing the
Network settings from within the Virtual Machine manually when using these
properties will trigger them to revert to the OVF specified settings on the next
reboot.

## Building OVF/OVA Image

A bash script is provided that runs the packer scripts and appends the xml
properties into the OVF file. When complete it uses ovftool to create a OVA
file.

This script is compatible with the 3 following VMware based provisioners:

* local - VMWare workstation, fusion, or player
* esxi - Non-vCenter managed ESXi host
* vcenter - vCenter

To use the bash script:

```bash
./build.sh <provisioner>
```

The generated OVF / OVA can be found in the directory: `__windows_server_2019`

### Example:

```bash
./build.sh esxi
```

## Initial Virtual Machine Boot

When a Virtual machine is created using the OVF/OVA generated by this script, it
will perform 2-3 reboots.

The first reboot performs the sysprep which regenerates the Windows SID and
initializes the OpenSSH service. When this is complete, it will reboot again.
While performing these operations, the VM will be using a DHCP acquired address.

If OVF properties were specified when the Virtual Machine was created, a 3rd
reboot will happen after these settings are applied.

## Default Administrator Credentials

* Username: Administrator
* Password: PaSsWoRd@1234

_**Note:** This password is intended for the initial connection by your
provisioning tools. This ideally should be changed with those tools._

If you want to change this default password in the build scripts, you will need
to modify the following files:

* autounattend.xml
* sysprep.xml
* esxi-provision.json
* local-provision.json
* vcenter-provision.json

## Automated Deployment Examples

The following examples demonstrate how to deploy the generated OVA using either
Ansible or GOVC.

### Ansible

**`tasks/main.yml`**

```yaml
---
- name: Get status of deployed Virtual Machines
  local_action:
    module: vmware_vm_info
    hostname: "{{esxi_hostname}}"
    username: "{{esxi_username}}"
    password: "{{esxi_password}}"
    validate_certs: false
    vm_type: vm
  register: vm_info

- name: Deploy Windows 2019 Server
  when: "win_vm_name not in (vm_info.virtual_machines | map(attribute='guest_name'))"
  local_action:
    module: vmware_deploy_ovf
    name: "{{win_vm_name}}"
    hostname: "{{esxi_hostname}}"
    username: "{{esxi_username}}"
    password: "{{esxi_password}}"
    validate_certs: false
    disk_provisioning: "{{esxi_disk_provisioning}}"
    ovf: "{{win_ova_path}}"
    networks:
      VM Network: "{{esxi_network}}"
    datastore: "{{esxi_datastore}}"
    fail_on_spec_warnings: true
    allow_duplicates: false
    power_on: false
    inject_ovf_env: true
    properties:
      vami.hostname.windows_server_2019: "{{win_hostname}}"
      vami.ip0.windows_server_2019: "{{win_ip_address}}"
      vami.netmask0.windows_server_2019: "{{win_ip_prefix}}"
      vami.gateway.windows_server_2019: "{{win_gateway}}"
      vami.dns.windows_server_2019: "{{win_dns_servers}}"
      vami.domain.windows_server_2019: "{{win_domain_name}}"
      vami.searchpath.windows_server_2019: "{{win_domain_name}}"

- name: Resize Windows 2019 Server
  when: "win_vm_name not in (vm_info.virtual_machines | map(attribute='guest_name'))"
  local_action:
    module: vmware_guest
    name: "{{win_vm_name}}"
    hostname: "{{esxi_hostname}}"
    username: "{{esxi_username}}"
    password: "{{esxi_password}}"
    validate_certs: false
    state: present
    hardware:
      memory_mb: "{{win_hw_memory}}"
      num_cpus: "{{win_hw_cpus}}"

- name: Power On Windows 2019 Server
  when: "win_vm_name not in (vm_info.virtual_machines | map(attribute='guest_name'))"
  local_action:
    module: vmware_guest
    name: "{{win_vm_name}}"
    hostname: "{{esxi_hostname}}"
    username: "{{esxi_username}}"
    password: "{{esxi_password}}"
    validate_certs: false
    state: poweredon
    wait_for_ip_address: false

- name: "Waiting for Windows 2019 Server VM to finish configuration..."
  local_action:
    module: wait_for
    host: "{{win_ip_address}}"
    port: 22
    state: started
    delay: 5
    sleep: 10
    timeout: 600
```

**`vars/main.yml`**

```yaml
# ESXi/vCenter API configuration
esxi_username: administrator@vsphere.local
esxi_password: password1
esxi_hostname: vcenter.lab.local
esxi_datastore: "datastore1"
esxi_network: "VM Network"
esxi_disk_provisioning: thin

# win vm options
win_vm_name: windows2019
win_ova_path: /path/to/windows_server_2019.ova
win_hw_cpus: 2
win_hw_memory: 2048

# win platform options
win_admin_password: PaSsWoRd@1234

# win networking configuration
win_hostname: winsrv01
win_ip_address: 192.168.10.10
win_ip_prefix: "24"
win_gateway: 192.168.10.1
win_dns_servers: 8.8.8.8,8.8.4.4
win_domain_name: lab.local
```

### GOVC

_**Note:** Requires
[govc](https://github.com/vmware/govmomi/tree/master/govc),
[python](https://realpython.com/installing-python/),
[jq](https://stedolan.github.io/jq/download/), and
nc (netcat) to be available in path._

```bash
#!/usr/bin/env bash

set -e

GOVC_INSECURE=true
GOVC_URL=vcenter.lab.local
GOVC_USERNAME=administrator@vsphere.local
GOVC_PASSWORD=password1
GOVC_DATASTORE=datastore1
GOVC_NETWORK="VM Network"
GOVC_DATACENTER=ha-datacenter

VM_OVA=/path/to/windows_server_2019.ova
VM_NAME=windows2019
VM_HOSTNAME=winsrv01
VM_IPADDR=192.168.10.10
VM_NETMASK=255.255.255.0
VM_GATEWAY=192.168.10.1
VM_DNS=8.8.8.8,8.8.4.4
VM_DOMAIN=lab.local
VM_SEARCHPATH=lab.local

# create json spec
JSON_SPEC=$(govc import.spec ${VM_OVA} | python -m json.tool)

# {
#     "DiskProvisioning": "flat",
#     "IPAllocationPolicy": "dhcpPolicy",
#     "IPProtocol": "IPv4",
#     "PropertyMapping": [
#         {
#             "Key": "vami.hostname.windows_server_2019",
#             "Value": ""
#         },
#         {
#             "Key": "vami.ip0.windows_server_2019",
#             "Value": ""
#         },
#         {
#             "Key": "vami.netmask0.windows_server_2019",
#             "Value": ""
#         },
#         {
#             "Key": "vami.gateway.windows_server_2019",
#             "Value": ""
#         },
#         {
#             "Key": "vami.dns.windows_server_2019",
#             "Value": ""
#         },
#         {
#             "Key": "vami.domain.windows_server_2019",
#             "Value": ""
#         },
#         {
#             "Key": "vami.searchpath.windows_server_2019",
#             "Value": ""
#         }
#     ],
#     "NetworkMapping": [
#         {
#             "Name": "VM Network",
#             "Network": ""
#         }
#     ],
#     "MarkAsTemplate": false,
#     "PowerOn": false,
#     "InjectOvfEnv": false,
#     "WaitForIP": false,
#     "Name": null
# }

# update json spec
JSON_SPEC=$(jq '.DiskProvisioning = "thin"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '.Name = "'"${VM_NAME}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '.InjectOvfEnv = true' <<<"${JSON_SPEC}")
# JSON_SPEC=$(jq '.WaitForIP = false' <<<"${JSON_SPEC}")
# JSON_SPEC=$(jq '.PowerOn = false' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.NetworkMapping[] | select(.Name == "VM Network") | .Network) |= "'"${GOVC_NETWORK}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.hostname.windows_server_2019") | .Value) |= "'"${VM_HOSTNAME}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.ip0.windows_server_2019") | .Value) |= "'"${VM_IPADDR}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.netmask0.windows_server_2019") | .Value) |= "'"${VM_NETMASK}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.gateway.windows_server_2019") | .Value) |= "'"${VM_GATEWAY}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.dns.windows_server_2019") | .Value) |= "'"${VM_DNS}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.domain.windows_server_2019") | .Value) |= "'"${VM_DOMAIN}"'"' <<<"${JSON_SPEC}")
JSON_SPEC=$(jq '(.PropertyMapping[] | select(.Key == "vami.searchpath.windows_server_2019") | .Value) |= "'"${VM_SEARCHPATH}"'"' <<<"${JSON_SPEC}")

# write json spec to temp location
JSON_SPEC_PATH="/tmp/${VM_NAME}_spec.json"
jq '.' <<<${JSON_SPEC} > ${JSON_SPEC_PATH}

# import ova with spec
govc import.ova -options=${JSON_SPEC_PATH} ${VM_OVA}

# power on vm
govc vm.power -on=true ${VM_NAME}

# wait for host to finish configuration
spin='-\|/'
i=0
until $(nc -4 -G 1 -z ${VM_IPADDR} 22 &> /dev/null); do
  i=$(( (i+1) %4 ))
  consolef.info "Waiting on ${VM_IPADDR}:22 to become reachable... ${spin:$i:1}"
  sleep 1
done

# cleanup temp spec file
rm -rf ${JSON_SPEC_PATH}
```

## License

Copyright (c) 2020

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
