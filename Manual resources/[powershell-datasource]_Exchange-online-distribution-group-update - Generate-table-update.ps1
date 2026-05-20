# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# variables configured in form:
$GroupType = "Distribution Group" # "Mail-enabled Security Group" or "Distribution Group"
$searchValue = $datasource.searchValue
$searchQuery = "*$searchValue*"

# PowerShell commands to import
$commands = @("Get-DistributionGroup")
#endregion init
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


try{
    #region check distribution group
    $actionMessage = "getting distribution groups"

    if (-not [String]::IsNullOrEmpty($searchValue)) {
        Write-Information "searchQuery: $searchQuery"

        switch ($GroupType) {
            "Distribution Group" { $recipientTypeDetails = "MailUniversalDistributionGroup" }
            "Mail-enabled Security Group" { $recipientTypeDetails = "MailUniversalSecurityGroup" }
            default { $recipientTypeDetails = $null }
        }

        $baseFilter = "Alias -like '$searchQuery' -or DisplayName -like '$searchQuery' -or Name -like '$searchQuery'"

        if ($null -ne $recipientTypeDetails) {
            $filterString = "{RecipientTypeDetails -eq '$recipientTypeDetails' -and ($baseFilter)}"
        }
        else {
            $filterString = "{$baseFilter}"
        }

        $DistributionGroupParams = @{
            Filter      = $filterString
            ResultSize  = "Unlimited"
            Verbose     = $false
            ErrorAction = "Stop"
        }

        $groups = Get-DistributionGroup @DistributionGroupParams

        $resultCount = @($groups).Count
        
        Write-Information "Result count: $resultCount"
        
        if ($resultCount -gt 0) {
            foreach ($group in $groups) {
                $returnObject = @{
                    name               = "$( $group.DisplayName )";
                    id                 = "$( $group.ExternalDirectoryObjectId )";
                    primarySmtpAddress = "$( $group.PrimarySmtpAddress )";
                    Alias              = "$( $group.alias )";
                }

                Write-Output $returnObject
            }
        }
    }
    #endregion check distribution group           
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = ($ex.ErrorDetails.Message | Convertfrom-json).error_description
    }
    else {
        $errorMessage = $($ex.Exception.message)
    }

    Write-Error "Error $actionMessage for Exchange Online distribution groups with the query [$searchQuery]. Error: $errorMessage"
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
#endregion lookup
