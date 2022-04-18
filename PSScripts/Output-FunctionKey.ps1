<#
.SYNOPSIS
Gets the available AKS upgrades and writes the information out to logs and a variable.  

.DESCRIPTION
Gets the available AKS upgrades and writes the information out to logs and a variable.  The az cli doesn't handle writing complex objects to Azure DevOps variables well so a simple count is outputted along with more detail to the logs.

.PARAMETER ResourceGroup
The AKS resource group

.PARAMETER AksServiceName
The AKS service name
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [String]$AzureSubscriptionId,
    [Parameter(Mandatory=$true)]
    [String]$ResourceGroup,
    [Parameter(Mandatory=$true)]
    [String]$FunctionAppName
)

$resourceId = "/subscriptions/$($AzureSubscriptionId)/resourceGroups/$($ResourceGroup)/providers/Microsoft.Web/sites/$($FunctionAppName)"
$functionKey = $(az rest --method post --uri "$($resourceId)/host/default/listKeys?api-version=2018-11-01" --query functionKeys.default -o tsv)


if ($null -ne $functionKey) {

    Write-Verbose "Function Key is $($functionKey)"
    Write-Output "##vso[task.setvariable variable=functionKey]$($functionKey)" 

}
else {

        Write-Verbose "function key has no value"

}
$GenerallyAvailableUpgrades