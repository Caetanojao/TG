$NetBoxUrl = "http://IP:PORTA/api"
$Token = "SEU_TOKEN_AQUI"

$Headers = @{
    "Authorization" = "Token $Token"
    "Content-Type"  = "application/json"
}

##########
# CLUSTER
##########

$clusterName = $env:COMPUTERNAME

$cluster = (Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/clusters/?name=$clusterName" -Headers $Headers).results

if (-not $cluster) {
    $clusterBody = @{
        name = $clusterName
        type = 1
    } | ConvertTo-Json

    $cluster = Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/clusters/" -Method POST -Headers $Headers -Body $clusterBody
}

$clusterId = $cluster.id

##########
# GET VMS 
##########

Get-VM | ForEach-Object {

    $vm = $_

    # CPU / MEM
    $cpu = (Get-VMProcessor -VMName $vm.Name).Count
    $memConfig = Get-VMMemory -VMName $vm.Name

    if ($memConfig.DynamicMemoryEnabled) {
    $memMB = [math]::Round($memConfig.Maximum / 1MB)
    } else {
    $memMB = [math]::Round($memConfig.Startup / 1MB)
    }

    #######
    # REDE
    #######

    $net = Get-VMNetworkAdapter -VMName $vm.Name

    $ip = $net.IPAddresses | Where-Object { $_ -match "\." } | Select-Object -First 1

    $rawMac = $net | Select-Object -ExpandProperty MacAddress -First 1

    if ($rawMac -and $rawMac.Length -eq 12) {
        $mac = ($rawMac.ToLower() -replace '(.{2})(?=.)','$1:').TrimEnd(':')
    } else {
        $mac = $null
    }

    ########
    # DISCO
    ########

    $disk = Get-VMHardDiskDrive -VMName $vm.Name | Select-Object -First 1

    if ($disk.Path) {
        $folder = Split-Path $disk.Path

        $sizeGB = (Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum / 1GB
    } else {
        $sizeGB = 0
    }

    $diskMB = [math]::Round($sizeGB * 1024)

    #########
    # SERIAL
    #########

    try {
        $bios = Get-WmiObject -Namespace "root\virtualization\v2" -Class Msvm_VirtualSystemSettingData |
        Where-Object { $_.ElementName -eq $vm.Name }

        $serial = $bios.BIOSSerialNumber
    } catch {
        $serial = ""
    }

    #####################
    # VM CREATE / UPDATE
    #####################

    $existingVM = (Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/virtual-machines/?name=$($vm.Name)" -Headers $Headers).results

    $vmBody = @{
        name    = $vm.Name
        cluster = $clusterId
        vcpus   = $cpu
        memory  = $memMB
        disk    = $diskMB
        serial  = $serial
        status  = "active"
    } | ConvertTo-Json

    if ($existingVM) {
        $vmId = $existingVM[0].id
        Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/virtual-machines/$vmId/" -Method PATCH -Headers $Headers -Body $vmBody
    } else {
        $newVM = Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/virtual-machines/" -Method POST -Headers $Headers -Body $vmBody
        $vmId = $newVM.id
    }

    #############
    # INTERFACE
    #############

    $ifaceName = "eth0"

    $iface = (Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/interfaces/?virtual_machine_id=$vmId&name=$ifaceName" -Headers $Headers).results

    if (-not $iface) {

        $ifaceBody = @{
            virtual_machine = $vmId
            name = $ifaceName
        } | ConvertTo-Json

        $iface = Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/interfaces/" -Method POST -Headers $Headers -Body $ifaceBody
        $ifaceId = $iface.id

    } else {
        $ifaceId = $iface[0].id
    }

    #################
    # MAC NO NETBOX
    #################

    $macId = $null

    if ($mac) {

        $existingMac = (Invoke-RestMethod -Uri "$NetBoxUrl/dcim/mac-addresses/?mac_address=$mac" -Headers $Headers).results

        if (-not $existingMac) {

            $macBody = @{
                mac_address = $mac
            } | ConvertTo-Json

            $newMac = Invoke-RestMethod -Uri "$NetBoxUrl/dcim/mac-addresses/" -Method POST -Headers $Headers -Body $macBody
            $macId = $newMac.id

        } else {
            $macId = $existingMac[0].id
        }

        # ASSOCIA MAC NA INTERFACE
        $updateIface = @{
            mac_address     = $macId
            primary_mac_address = $macId
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/interfaces/$ifaceId/" -Method PATCH -Headers $Headers -Body $updateIface
    }

    ######
    # IP
    ######

    if ($ip) {

        $existingIP = (Invoke-RestMethod -Uri "$NetBoxUrl/ipam/ip-addresses/?address=$ip" -Headers $Headers).results

        if (-not $existingIP) {

            $ipBody = @{
                address = "$ip/24"
                assigned_object_type = "virtualization.vminterface"
                assigned_object_id   = $ifaceId
            } | ConvertTo-Json

            $ipObj = Invoke-RestMethod -Uri "$NetBoxUrl/ipam/ip-addresses/" -Method POST -Headers $Headers -Body $ipBody

        } else {
            $ipObj = $existingIP[0]
        }

        # definir IP primário
        $primaryBody = @{
            primary_ip4 = $ipObj.id
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$NetBoxUrl/virtualization/virtual-machines/$vmId/" -Method PATCH -Headers $Headers -Body $primaryBody
    }

    Write-Host "VM sincronizada: $($vm.Name)"
}
