# Variables configured in form
$searchValue = $datasource.searchValue
if ([string]::IsNullOrEmpty($searchValue) -or $searchValue -eq "*") {
    $filter = "RecipientTypeDetails -eq 'MailUniversalDistributionGroup' -or RecipientTypeDetails -eq 'MailUniversalSecurityGroup'"
}
else {
    $escapedSearchValue = $searchValue.Replace("'", "''")
    $filter = "(Name -like '*$escapedSearchValue*' -or Alias -like '*$escapedSearchValue*' -or PrimarySmtpAddress -like '*$escapedSearchValue*') -and (RecipientTypeDetails -eq 'MailUniversalDistributionGroup' -or RecipientTypeDetails -eq 'MailUniversalSecurityGroup')"
}

# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Id"
    , "Guid"
    , "ExchangeGuid"
    , "ExternalDirectoryObjectId"
    , "DisplayName"
    , "PrimarySmtpAddress"
    , "EmailAddresses"
    , "Alias"
    , "RecipientTypeDetails"
)

# PowerShell commands to import
# Use Get-EXORecipient because it is faster and supports server-side filtering
$commands = @(
    "Get-Recipient"
    , "Get-EXORecipient"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    $actionMessage = "importing module [ExchangeOnlineManagement]"
    $importModuleSplatParams = @{
        Name        = "ExchangeOnlineManagement"
        Cmdlet      = $commands
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $null = Import-Module @importModuleSplatParams

    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"

    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword

    # Connect to Microsoft Exchange Online
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

    # Get groups
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-exorecipient?view=exchange-ps
    $actionMessage = "querying distribution groups and mail-enabled security groups that match filter [$($filter)]"

    $getGroupsSplatParams = @{
        ResultSize  = "Unlimited"
        Filter      = $filter
        Properties  = $propertiesToSelect
        ErrorAction = 'Stop'
    }

    $groups = Get-EXORecipient @getGroupsSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried distribution groups and mail-enabled security groups that match filter [$($filter)]. Result count: $(($groups | Measure-Object).Count)"

    # Sort and Send results to HelloID
    $actionMessage = "sending results to HelloID"
    $groups | Sort-Object -Property DisplayName | ForEach-Object {
        $groupType = switch ($_.RecipientTypeDetails) {
            "MailUniversalDistributionGroup" { "Distribution Group" }
            "MailUniversalSecurityGroup" { "Mail-enabled Security Group" }
            default { "$($_.RecipientTypeDetails)" }
        }

        Write-Output @{
            Id                        = $_.Id
            Guid                      = $_.Guid
            ExchangeGuid              = $_.ExchangeGuid
            ExternalDirectoryObjectId = $_.ExternalDirectoryObjectId
            DisplayName               = $_.DisplayName
            PrimarySmtpAddress        = $_.PrimarySmtpAddress
            EmailAddresses            = $_.EmailAddresses
            Alias                     = $_.Alias
            RecipientTypeDetails      = $_.RecipientTypeDetails
            GroupType                 = $groupType
            mailPrefix                = ($_.PrimarySmtpAddress -split '@')[0]
            mailSuffix                = ($_.PrimarySmtpAddress -split '@')[1]
        }
    } 
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
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/disconnect-exchangeonline?view=exchange-ps
    $deleteExchangeSessionSplatParams = @{
        Confirm     = $false
        ErrorAction = "Stop"
    }
    $null = Disconnect-ExchangeOnline @deleteExchangeSessionSplatParams
}
