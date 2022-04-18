<#
.SYNOPSIS
Removes an Sql Server 

.DESCRIPTION
Removes an Sql Server

.PARAMETER ContainerResourceGroupName
The name of the resource group

.PARAMETER KeyVaultResourceGroupName
The name of the resource group

.PARAMETER ContainerRegistryName
Add theserver nae

.PARAMETER KeyVaultName
The name of the resource group

.PARAMETER KeyName
Add theserver nae
#>


[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [String]$ContainerResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String]$KeyVaultResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String]$ContainerRegistryName,
    [Parameter(Mandatory=$true)]
    [String]$KeyVaultName,
    [Parameter(Mandatory=$true)]
    [String]$KeyName
)

$registry = Get-AzContainerRegistry -Name $ContainerRegistryName -ResourceGroupName $ContainerResourceGroupName
if (!$registry) {

    Write-Verbose "$($ContainerRegistryName) container registry not found"
    throw "$($ContainerRegistryName) container registry not found"

}

$keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $KeyVaultResourceGroupName
if (!$keyVault) {

    Write-Verbose "$($keyVault) key vault  not found"
    throw "$($keyVault) key vault not found"

} 

Write-Verbose "Retrieving container registry key for $($ContainerRegistryName)"
Write-Output  "Retrieving container registry key for $($ContainerRegistryName)"

$creds = Get-AzContainerRegistryCredential -Registry $registry

$secretValue = ConvertTo-SecureString $creds.Password -AsPlainText -Force

# $currentSecret = Get-AzKeyVaultSecret  -VaultName $KeyVaultName -Name $KeyName
# if($currentSecret){
#     Remove-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyName -Force
#     Remove-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyName -InRemovedState -Force 
# }

Write-Verbose "Storing container registry key for $($ContainerRegistryName) into the $($KeyName) secret of $($KeyVaultName)"
Write-Output  "Storing container registry key for $($ContainerRegistryName) into the $($KeyName) secret of $($KeyVaultName)"

Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyName -SecretValue $secretValue

Write-Verbose "Stored container registry key for $($ContainerRegistryName) into the $($KeyName) secret of $($KeyVaultName)"
Write-Output  "Stored container registry key for $($ContainerRegistryName) into the $($KeyName) secret of $($KeyVaultName)"




