<#
.SYNOPSIS
Creates the Service Principals and App Registrations required by an Azure Kubernetes Cluster

.DESCRIPTION
Creates the Service Principals and App Registrations required by an Azure Kubernetes Cluster.  The Application (Client) IDs are written out to Azure DevOps variables to be consumed by later steps in the pipeline.

.PARAMETER AcrResourceGroup
The resource group where the Azure Container Registry that this AKS cluster will use resides

.PARAMETER AksServicePrincipalName
The name of the AAD Service Principal that will be granted Contributor rights on the Azure Subscription that the AKS cluster resides in.
If executed from Azure DevOps this will be the default subscription of the Azure DevOps Service Principal.  The name should be in the format prg-<env>-shared-aks-svc.

.PARAMETER AksAdClientApplicationName
The name of the AAD Application registration that will be granted permissions user_impersonation on the AksAdServerApplicationName app registration.  The name should be in the format prg-<env>-shared-aks-client.

.PARAMETER AksAdServerApplicationName
The name of the AAD Application registration that will be granted permissions on the Microsoft Graph API to interact with AAD on behalf of the AKS cluster.
The permissions granted will be Directory.Read.All and User.Read.  The name should be in the format prg-<env>-shared-aks-api.

.PARAMETER AksServicePrincipalManagedRgs
An array of resource group names that the AksServicePrincipal will be assigned the Contributor role on.  
The service principal requires this role on the resource group it's VNet is deployed into and the resource group it's nodes are created in.

.PARAMETER AksResourceGroup
The resource group that will hold the AKS service and it's VNet

.PARAMETER MonDevOpsScriptRoot
The path to the PSScripts folder in the local copy of the prg-devops repo, eg $(System.DefaultWorkingDirectory)/_olusola-adio_prg-devops/PSScripts in an Azure DevOps task

.PARAMETER SharedKeyVaultName
The name of the KeyVault where the App Registration secrets will be stored.  Must be in the same tenant.

.NOTES
These documents are generally for Azure CLI rather than PowerShell but are a useful reference point
AksServicePrincipalName: https://docs.microsoft.com/en-us/azure/aks/kubernetes-service-principal
AksAdClientApplicationName & AksAdServerApplicationName: https://docs.microsoft.com/en-us/azure/aks/azure-ad-integration-cli
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [String]$AcrResourceGroup,
    [Parameter(Mandatory = $true)]
    [String]$AksAdClientApplicationName,
    [Parameter(Mandatory = $true)]
    [String]$AksAdServerApplicationName,
    [Parameter(Mandatory = $true)]
    [String]$AksResourceGroup,
    [Parameter(Mandatory = $true)]
    [String]$AksServicePrincipalName,
    [Parameter(Mandatory = $true)]
    [String]$MonDevOpsScriptRoot,
    [Parameter(Mandatory = $true)]
    [String]$SharedKeyVaultName
)

function Set-SpnResourceGroupRoleAssignment {
    [CmdletBinding()]
    param(
        $ResourceGroup,
        $RoleDefinitionName,
        $ServicePrincipalObjectId
    )

    $spnResourceGroup = Get-AzureRmResourceGroup -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
    if ($spnResourceGroup) {
        $ExistingAssignment = Get-AzureRmRoleAssignment -ObjectId $ServicePrincipalObjectId -RoleDefinitionName $RoleDefinitionName -ResourceGroupName $ResourceGroup
        if ($ExistingAssignment) {

            Write-Verbose "$($ExistingAssignment.DisplayName) is assigned $($ExistingAssignment.RoleDefinitionName) on $ResourceGroup"

        }
        else {

            Write-Verbose "Assigning '$RoleDefinitionName' to $ServicePrincipalObjectId on $ResourceGroup"
            # Service Principal isn't immediately available to add role to
            Start-Sleep -Seconds 15
            New-AzureRmRoleAssignment -ObjectId $ServicePrincipalObjectId -RoleDefinitionName $RoleDefinitionName -ResourceGroupName $ResourceGroup

        }
    }
    else {
        Write-Warning "No access to $ResourceGroup, unable to assert if $ServicePrincipalObjectId has role $RoleDefinitionName"
    }
}

$LogFile = New-Item -Path $MonDevOpsScriptRoot -Name "$Env:Environment_Name-Logfile.log" -Force
Start-Transcript -Path $LogFile

$Context = Get-AzureRmContext

# Create role definition to allow creation of new Resource Groups by service principal
if (!(Get-AzureRmRoleDefinition -Name "Resource Group Contributor")) {

    Write-Verbose "Creating Resource Group Contributor role"
    $Role = Get-AzureRmRoleDefinition -Name Reader
    $Role.Name = "Resource Group Contributor"
    $Role.Description = "Lets you create new resource groups but not add to, delete or modify them"
    $Role.IsCustom = $true
    $Role.Actions = "Microsoft.Resources/subscriptions/resourceGroups/write"
    $Role.AssignableScopes = "/subscriptions/$($Context.Subscription.Id)"
    New-AzureRmRoleDefinition -Role $Role

}

# Create Service Principal with Contributor on AKS resource group and Resource Group Contributor on the Subscription.  AKS needs to be able to create the resource group that contains it's nodes, the ARM deployment will error if this resource group has already been created.
$AksServicePrincipal = & "$MonDevOpsScriptRoot/New-ApplicationRegistration.ps1" -AppRegistrationName $AksServicePrincipalName -AddSecret -KeyVaultName $SharedKeyVaultName -Verbose
$ExistingAssignment = Get-AzureRmRoleAssignment -ObjectId $AksServicePrincipal.Id -RoleDefinitionName "Resource Group Contributor" -Scope "/subscriptions/$($Context.Subscription.Id)"
if ($ExistingAssignment) {

    Write-Verbose "$($ExistingAssignment.DisplayName) is assigned $($ExistingAssignment.RoleDefinitionName) on /subscriptions/$($Context.Subscription.Id)"

}
else {

    Write-Verbose "Assigning 'Resource Group Contributor' to $($AksServicePrincipal.Id) on /subscriptions/$($Context.Subscription.Id)"
    # Service Principal isn't immediately available to add role to
    Start-Sleep -Seconds 15
    New-AzureRmRoleAssignment -ObjectId $AksServicePrincipal.Id -RoleDefinitionName "Resource Group Contributor" -Scope "/subscriptions/$($Context.Subscription.Id)"

}
Set-SpnResourceGroupRoleAssignment -ResourceGroup $AksResourceGroup -RoleDefinitionName "Network Contributor" -ServicePrincipalObjectId $AksServicePrincipal.Id
Set-SpnResourceGroupRoleAssignment -ResourceGroup $AcrResourceGroup -RoleDefinitionName "AcrPull" -ServicePrincipalObjectId $AksServicePrincipal.Id

$AllAssignments = Get-AzureRmRoleAssignment -ObjectId $AksServicePrincipal.Id
# Validates that the AksServicePrincipal has only been assigned 2 roles (One for prg-<env>-shared-rg, the other for prg-<env>-shared-aksnodes-rg).
if ($AllAssignments.Count -gt 3) {

    Write-Warning "AksServicePrincipal has been assigned additional roles, please review"

}
Write-Verbose "Writing AksServicePrincipal ApplicationId value [$($AksServicePrincipal.ApplicationId)] to variable AksServicePrincipalClientId"
Write-Output "##vso[task.setvariable variable=AksServicePrincipalClientId]$($AksServicePrincipal.ApplicationId)"

# Create Service Principal with Delegated Permissions Directory.Read.All & User.Read and Application Permissions Directory.Read.All
$AksAdServerApplication = & $MonDevOpsScriptRoot/New-ApplicationRegistration.ps1 -AppRegistrationName $AksAdServerApplicationName -AddSecret -KeyVaultName $SharedKeyVaultName -Verbose
# Service Principal isn't immediately available to add API permissions to
Start-Sleep -Seconds 15
& $MonDevOpsScriptRoot/Add-AzureAdApiPermissionsToApp.ps1 -AppRegistrationDisplayName $AksAdServerApplicationName -ApiName "Microsoft Graph" -ApplicationPermissions "Directory.Read.All" -DelegatedPermissions "Directory.Read.All", "User.Read" -Verbose
Write-Verbose "Writing AksAdServerApplication ApplicationId value [$($AksAdServerApplication.ApplicationId)] to variable AksRbacServerAppId"
Write-Output "##vso[task.setvariable variable=AksRbacServerAppId]$($AksAdServerApplication.ApplicationId)"

# Create Service Principal with Delegated user_impersonation on $AksAdServerApplication
$AksAdClientApplicationSpn = & $MonDevOpsScriptRoot/New-ApplicationRegistration.ps1 -AppRegistrationName $AksAdClientApplicationName -Verbose
# Service Principal isn't immediately available to add API permissions to
Start-Sleep -Seconds 15
& $MonDevOpsScriptRoot/Add-AzureAdApiPermissionsToApp.ps1 -AppRegistrationDisplayName $AksAdClientApplicationName -ApiName $AksAdServerApplication.DisplayName -DelegatedPermissions "user_impersonation" -Verbose
# Set the allowPublicClient property of the App Registration to true.  This step depends on the token for Microsoft Graph obtained during the execution of Add-AzureAdApiPermissionsToApp.ps1
$AksAdClientApplication = Get-AzureRmADApplication -DisplayName $AksAdClientApplicationSpn.DisplayName
Write-Verbose "Setting allowPublicClient on $($AksAdClientApplicationSpn.DisplayName) [$($AksAdClientApplication.ObjectId)] to true"
Set-AzureADApplication -ObjectId $AksAdClientApplication.ObjectId -PublicClient $true
Write-Verbose "Writing AksAdClientApplicationSpn ApplicationId value [$($AksAdClientApplicationSpn.ApplicationId)] to variable AksRbacClientAppId"
Write-Output "##vso[task.setvariable variable=AksRbacClientAppId]$($AksAdClientApplicationSpn.ApplicationId)"

Stop-Transcript

Write-Verbose "Getting logs from $($LogFile.FullName)"
$Logs = Get-Content -Path $LogFile
if ($Logs -match "Registering service principal ...") {

    Write-Verbose "Service Principal creation detected in logs, manual steps required, see prg-shared README.md"
    throw "Service Principal permissions needs approving and variables may need to be created or updated in Azure DevOps, see prg-shared README.md"

}
else {

    Write-Verbose "Service Principal creation not detected in logs"

}