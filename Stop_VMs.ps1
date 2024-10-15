# Variables
$KeyVaultName = "<my-keyvault-name>"
$KeyVaultSecretsn = "SubscriptionName"
$KeyVaultSecretrg = "resourceGroupName" 
$storageType = "Standard_LRS" 
$maxRetries = 2                       
$retryDelaySeconds = 50         
$tagName = "environment"
$tagValue = "avd"    

Write-Output "Verifying Managed Identity for script"

# Prvevent inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process | Out-Null

# Connect using a Managed Service Identity (system assigned)
try {
        Connect-AzAccount -Identity
        Write-Output "Using system-assigned managed identity"
		# Retrieving credentials with Azure Key Vault
		$SubscriptionName = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretsn -AsPlainText
		$resourceGroupName = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretrg -AsPlainText
    }
catch {
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

# set and store script context
Set-AzContext -SubscriptionName $SubscriptionName

Write-Output "Starting Auto-Stop VM script"

function Stop-VMFunction {
	param ([string]$vmName)
    $retryCount = 0      
    $success = $false  
       
    while ($retryCount -lt $maxRetries) {
        Write-Output "Stop VM: $vmName (Retry $($retryCount+1))"
        Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
        Start-Sleep -Seconds $retryDelaySeconds

        $vmStatus = (Get-AzResource -ResourceId (Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName).Id).Properties.ProvisioningState

        if ($vmStatus -eq "Succeeded") {
            $success = $true
            break
         } else {
            Write-Output "Failed to Stop VM: $vmName (Retry $($retryCount+1))"
        }         
        $retryCount++ 
    }

    if ($success) {
        Write-Output "VM $vmName Stopped successfully"     
     } else {
        Write-Output "Failed to Stop VM $vmName after $maxRetries retries"
    }
}

# Get VMs based on specific tagName and tagValue in a resource group
$vmList = Get-AzVM -ResourceGroupName $resourceGroupName | Where-Object {$_.Tags.Keys -contains $tagName -and $_.Tags.Values -contains $tagValue} | Select-Object -ExpandProperty Name

foreach ($vmName in $vmList) {
    Stop-VMFunction -vmName $vmName
    $vm = Get-AzVM -Name $vmName -resourceGroupName $resourceGroupName
    $vmDisks = Get-AzDisk -ResourceGroupName $resourceGroupName

    # Convert Disk to Standard HDD Storage
    foreach ($disk in $vmDisks)
    {
     if ($disk.ManagedBy -eq $vm.Id) {
        $diskUpdateConfig = New-AzDiskUpdateConfig –AccountType $storageType
        Update-AzDisk -DiskUpdate $diskUpdateConfig -ResourceGroupName $resourceGroupName -DiskName $disk.Name
       }
    }
}

Write-Output "Auto-Stop VM script completed"
