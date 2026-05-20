# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# variables configured in form:
$exchangeDGGUID = $form.gridGroup.Guid
$currentAddresses = $form.gridGroup.EmailAddresses
$displayName = $form.displayName
$alias = $form.alias
$mailboxMailPrefix = $form.mailPrefix
$mailboxMailDomain = $form.mailDomain.id
$blnSetAsPrimaryEmail = if ([string]::IsNullOrWhiteSpace($form.blnSetAsPrimaryEmail)) { $false } else { [System.Convert]::ToBoolean($form.blnSetAsPrimaryEmail) }
# Build proxy address with appropriate prefix based on whether it should be primary
if ($blnSetAsPrimaryEmail) {
    $mailboxProxyAddress = "SMTP:$($mailboxMailPrefix)@$($mailboxMailDomain)"
}
else {
    $mailboxProxyAddress = "smtp:$($mailboxMailPrefix)@$($mailboxMailDomain)"
}

# PowerShell commands to import
$commands = @("Set-DistributionGroup")
#endregion init

#region functions

#endregion functions

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param()
    try {
        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

#region Import module & connect
try {    
    $actionMessage = "importing module [ExchangeOnlineManagement]"
    $importModuleSplatParams = @{
        Name        = "ExchangeOnlineManagement"
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $null = Import-Module @importModuleSplatParams

    #region Retrieving certificate
    $actionMessage = "retrieving certificate"
    $certificate = Get-MSEntraCertificate
    #endregion Retrieving certificate
    
    #region Connect to Microsoft Exchange Online
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/connect-exchangeonline?view=exchange-ps
    $actionMessage = "connecting to Microsoft Exchange Online"
    $createExchangeSessionSplatParams = @{
        Organization          = $EntraIdOrganization
        AppID                 = $EntraIdAppId
        Certificate           = $certificate
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        SkipLoadingCmdletHelp = $true
        SkipLoadingFormatData = $true
        ErrorAction           = "Stop"
    }
    $null = Connect-ExchangeOnline @createExchangeSessionSplatParams
    Write-Information "Connected to Microsoft Exchange Online"
} 
catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"        
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}



#region get distribution group
try {
    # Get current email addresses and prepare new email address list, while keeping existing proxy addresses (except the current address if already present)
    $proxyAddresses = @()
    
    # Extract the email address without prefix for comparison
    $emailAddressOnly = $mailboxProxyAddress -replace '^(smtp|SMTP):', ''
    
    foreach ($address in $currentAddresses) {
        # If setting as primary, convert any existing primary SMTP to secondary
        if ($blnSetAsPrimaryEmail -and $address.StartsWith('SMTP:')) {
            $address = $address -replace 'SMTP:', 'smtp:'
        }
        # Remove the address if it already exists (to avoid duplicates)
        if ($address -ne "smtp:$emailAddressOnly" -and $address -ne "SMTP:$emailAddressOnly") {
            $proxyAddresses += $address
        }
    }
    # Add the new proxy address
    $proxyAddresses += $mailboxProxyAddress

    #region update distribution group
    $actionMessage = "updating distribution group"

    $UpdateDistributionGroupParams = @{
        Identity                        = $exchangeDGGUID
        DisplayName                     = $displayName
        Name                            = $displayName
        EmailAddresses                  = $proxyAddresses
        Alias                           = $alias
        BypassSecurityGroupManagerCheck = $true    
        ErrorAction                     = 'Stop'
    }

    Set-DistributionGroup @UpdateDistributionGroupParams
 
    Write-Information  "Distribution Group [$displayName] updated successfully" 
    $Log = @{
        Action            = "UpdateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange Online" # optional (free format text) 
        Message           = "Distribution Group [$displayName] updated successfully"  # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $displayName # optional (free format text) 
        TargetIdentifier  = $([string]$exchangeDGGUID) # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log 
}
catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    $Log = @{
        Action            = "UpdateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange Online" # optional (free format text) 
        Message           = "Error $actionMessage for Exchange Online distribution group [$name]" # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $name # optional (free format text) 
        TargetIdentifier  = $([string]$exchangeDGGUID) # optional (free format text) 
    }
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/disconnect-exchangeonline?view=exchange-ps
    $deleteExchangeSessionSplatParams = @{
        Confirm     = $false
        ErrorAction = "Stop"
    }
    $null = Disconnect-ExchangeOnline @deleteExchangeSessionSplatParams
    Write-Information "Disconnected from Microsoft Exchange Online"
}
