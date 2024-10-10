# Variables
$SubscriptionName = "a70301c3-f1c3-4a37-9a4d-660ccefa6793"               
$resourceGroupName = "rg-liquit-prod-we-01"
$storageType = "Premium_LRS" 
$maxRetries = 2                       
$retryDelaySeconds = 50
$tagName = "environment"
$tagValue = "avd"               

# Prvevent inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process | Out-Null

# Connect using a Managed Service Identity (system assigned)
try {
        Connect-AzAccount -Identity
        Write-Output "Using system-assigned managed identity"
    }
catch {
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

# set and store script context
Set-AzContext -SubscriptionName $SubscriptionName

Write-Output "Starting Auto-Start VM script"

function Start-VMFunction {
    param (
        [string]$vmName
    )

    $retryCount = 0      
    $success = $false   
       
    while ($retryCount -lt $maxRetries) {
        Write-Output "Starting VM: $vmName (Retry $($retryCount+1))"
        Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -NoWait
        Start-Sleep -Seconds $retryDelaySeconds
 
        $vmStatus = (Get-AzResource -ResourceId (Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName).Id).Properties.ProvisioningState

        if ($vmStatus -eq "Succeeded") {
            $success = $true
            break
        }
        else {
            Write-Output "Failed to start VM: $vmName (Retry $($retryCount+1))"
        }
         
        $retryCount++   

    if ($success) {
        Write-Output "VM $vmName started successfully"
    }
    else {
        Write-Output "Failed to start VM $vmName after $maxRetries retries"
    }
}

# Get only the VMs in the resource group based on a specifix tagName and tagValue
$vmList = Get-AzVM -ResourceGroupName $resourceGroupName | where {$_.Tags.Keys -contains $tagName -and $_.Tags.Values -contains $tagValue} | Select-Object -ExpandProperty Name

foreach ($vmName in $vmList) {
    $vm = Get-AzVM -Name $vmName -resourceGroupName $resourceGroupName

    $vmDisks = Get-AzDisk -ResourceGroupName $resourceGroupName

    # Convert Disk to Premium storage
    foreach ($disk in $vmDisks)
    {
     if ($disk.ManagedBy -eq $vm.Id)
     {
        $diskUpdateConfig = New-AzDiskUpdateConfig –AccountType $storageType
        Update-AzDisk -DiskUpdate $diskUpdateConfig -ResourceGroupName $resourceGroupName `
        -DiskName $disk.Name
     }
    }
    Start-VMFunction -vmName $vmName 
}

Write-Output "Auto-Start VM script completed"