$identity = $form.gridGroup.ExternalDirectoryObjectId
$usersToAdd = $form.permissionList.leftToRight
$usersToRemove = $form.permissionList.rightToLeft

# PowerShell commands to import
$commands = @(
    "Get-EXORecipient",
    "Add-DistributionGroupMember",
    "Remove-DistributionGroupMember"
)

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            # $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message # Does not show the correct error message for the Raet IAM API calls
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message

        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [HelloID.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}

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
#endregion functions

#region Import module & connect
try {    
    $actionMessage = "importing module [ExchangeOnlineManagement]"
    $importModuleSplatParams = @{
        Name        = "ExchangeOnlineManagement"
        Cmdlet      = $commands
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

#region Get Distributiongroup
try {
    $exchangeQuerySplatParams = @{
        Identity    = $identity
        ErrorAction = "Stop"
    }

    Write-Information "Querying distribution group with identity [$identity]"
    $Group = Get-EXORecipient @exchangeQuerySplatParams

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
    $log = @{
        Action            = "undefined" # optional. ENUM (undefined = default) 
        System            = "ExchangeOnline" # optional (free format text) 
        Message           = $auditMessage # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = "$($form.gridGroup.DisplayName)" # optional (free format text) 
        TargetIdentifier  = "$($form.gridGroup.ExternalDirectoryObjectId)" # optional (free format text) 
    }
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
    exit # use when using multiple try/catch and the script must stop
}
#endregion Get Distributiongroup


#region Grant selected users to distribution group
foreach ($userToAdd in $usersToAdd) {
    try {
        Write-Verbose "Granting access to distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToAdd.UserPrincipalName) ($($userToAdd.guid))]"

        $addMemberSplatParams = @{
            Identity    = $group.ExternalDirectoryObjectId
            Member      = $userToAdd.Guid
            ErrorAction = "SilentlyContinue"
        }

        $null = Add-DistributionGroupMember @addMemberSplatParams

        Write-Information "Successfully granted access to distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToAdd.UserPrincipalName) ($($userToAdd.guid))]"

        # Audit log for HelloID
        $Log = @{
            Action            = "GrantMembership" # optional. ENUM (undefined = default) 
            System            = "Exchange" # optional (free format text) 
            Message           = "Successfully granted access to distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToAdd.UserPrincipalName) ($($userToAdd.guid))]" # required (free format text) 
            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $group.DisplayName # optional (free format text)
            TargetIdentifier  = $([string]$group.ExternalDirectoryObjectId) # optional (free format text)
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
        $log = @{
            Action            = "undefined" # optional. ENUM (undefined = default) 
            System            = "ExchangeOnline" # optional (free format text) 
            Message           = $auditMessage # required (free format text) 
            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = "$($userToAdd.displayValue)" # optional (free format text) 
            TargetIdentifier  = "$($userToAdd.guid)" # optional (free format text) 
        }
        Write-Information -Tags "Audit" -MessageData $log
        Write-Warning $warningMessage
        Write-Error $auditMessage
        # exit # use when using multiple try/catch and the script must stop
    }
}

#region Revoke selected users from distribution group
foreach ($userToRemove in $usersToRemove) {
    try {
        Write-Verbose "Revoking permission from distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToRemove.UserPrincipalName) ($($userToRemove.guid))]"

        $removeMemberSplatParams = @{
            Identity    = $group.ExternalDirectoryObjectId
            Member      = $userToRemove.Guid
            Confirm     = $false
            ErrorAction = "SilentlyContinue"
        }

        $null = Remove-DistributionGroupMember @removeMemberSplatParams

        Write-Information "Successfully revoked permission from distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToRemove.UserPrincipalName) ($($userToRemove.guid))]"

        # Audit log for HelloID
        $Log = @{
            Action            = "RevokeMembership" # optional. ENUM (undefined = default) 
            System            = "Exchange" # optional (free format text) 
            Message           = "Successfully revoked permission from distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToRemove.UserPrincipalName) ($($userToRemove.guid))]" # required (free format text) 
            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $group.DisplayName # optional (free format text)
            TargetIdentifier  = $([string]$group.ExternalDirectoryObjectId) # optional (free format text)
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
        $log = @{
            Action            = "undefined" # optional. ENUM (undefined = default) 
            System            = "ExchangeOnline" # optional (free format text) 
            Message           = $auditMessage # required (free format text) 
            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = "$($userToRemove.displayValue)" # optional (free format text) 
            TargetIdentifier  = "$($userToRemove.guid)" # optional (free format text) 
        }
        Write-Information -Tags "Audit" -MessageData $log
        Write-Warning $warningMessage
        Write-Error $auditMessage
        # exit # use when using multiple try/catch and the script must stop
    }
}

#Remove Exchange session
# Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/disconnect-exchangeonline?view=exchange-ps
$deleteExchangeSessionSplatParams = @{
    Confirm     = $false
    ErrorAction = "Stop"
}
$null = Disconnect-ExchangeOnline @deleteExchangeSessionSplatParams
Write-Information "Disconnected from Microsoft Exchange Online"

