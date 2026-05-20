# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$outputText = [System.Collections.Generic.List[PSCustomObject]]::new()

# variables configured in form:
$Name = $datasource.Name
$currentName = $datasource.SelectedSM.Name
$currentPrimarySmtpAddress = $datasource.SelectedSM.primarySmtpAddress
$currentExchangeGuid = $datasource.SelectedSM.id
$PrimarySmtpAddress = $datasource.PrimarySmtpAddress
$currentAlias = $datasource.SelectedSM.alias
$Alias = $datasource.Alias
$Domain = $PrimarySmtpAddress -Split '@'
$Domain = $Domain[1]

# PowerShell commands to import
$commands = @("Get-User", "Get-DistributionGroup")
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


try {
    if (($currentName -eq $Name) -and ($currentPrimarySmtpAddress -eq $PrimarySmtpAddress) -and ($currentAlias -eq $Alias)) {
        $outputText.Add([PSCustomObject]@{
                Message = "Name [$currentName] not changed"
                IsError = $true
            })
        $outputText.Add([PSCustomObject]@{
                Message = "PrimarySmtpAddress [$currentPrimarySmtpAddress] not changed"
                IsError = $true
            })
        $outputText.Add([PSCustomObject]@{
                Message = "Alias [$currentAlias] not changed"
                IsError = $true
            })
    }

    if (-not($outputText.isError -contains - $true)) {
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
        
        # Prepare query params for distribution groups (scan all to validate uniqueness)
        $DistributionGroupParams = @{
            ResultSize  = 'Unlimited'
            ErrorAction = 'Stop'
        }

        $DistributionGroups = Get-DistributionGroup @DistributionGroupParams

        if (-not $DistributionGroups) {
            Write-Information  "Distribution Group [$Name] is available"
            $outputText.Add([PSCustomObject]@{
                    Message = "Distribution Group [$Name] is available"
                    IsError = $false
                })
        }     
        else {
            foreach ($record in $DistributionGroups) {
                # Determine a stable identifier for the group (prefer ExternalDirectoryObjectId, then Guid, then Identity)
                $recordId = $record.ExternalDirectoryObjectId
                if (-not $recordId) { $recordId = $record.Guid }
                if (-not $recordId) { $recordId = $record.Identity }

                if ((($record.Name -eq $Name) -or ($record.DisplayName -eq $Name)) -and ($recordId -ne $currentExchangeGuid)) {
                    $outputText.Add([PSCustomObject]@{
                            Message = "Name [$Name] not unique, found on [$($record.Name)]"
                            IsError = $true
                        })
                }
                if (($record.Alias -eq $Alias) -and ($recordId -ne $currentExchangeGuid)) {
                    $outputText.Add([PSCustomObject]@{
                            Message = "Alias [$Alias] not unique, found on [$($record.Name)]"
                            IsError = $true
                        })
                }
                if ((($record.EmailAddresses -eq "SMTP:$PrimarySmtpAddress") -or ($record.ProxyAddresses -eq "smtp:$PrimarySmtpAddress")) -and ($recordId -ne $currentExchangeGuid)) {
                    $outputText.Add([PSCustomObject]@{
                            Message = "PrimarySmtpAddress [$PrimarySmtpAddress] not unique, found on [$($record.Name)]"
                            IsError = $true
                        })
                }
                elseif (($record.EmailAddresses -eq "SMTP:$Alias@$Domain") -or ($record.ProxyAddresses -eq "smtp:$Alias@$Domain") -and ($recordId -ne $currentExchangeGuid)) {
                    $outputText.Add([PSCustomObject]@{
                            Message = "ProxyAddress [$Alias@$Domain] not unique, found on [$($record.Name)]"
                            IsError = $true
                        })
                }
            }
        }
        #endregion check distribution group           
    }

    if ($outputText.isError -contains - $true) {
        $outputMessage = "Invalid"
    }
    else {
        $outputMessage = "Valid"
        $outputText.Add([PSCustomObject]@{
                Message = "Name [$Name] unique"
                IsError = $false
            })
        $outputText.Add([PSCustomObject]@{
                Message = "Alias [$Alias] unique"
                IsError = $false
            })
        $outputText.Add([PSCustomObject]@{
                Message = "PrimarySmtpAddress [$PrimarySmtpAddress] unique"
                IsError = $false
            })
    }

    foreach ($text in $outputText) {
        $outputMessage += " | " + $($text.Message)
    }

    $returnObject = @{
        text = $outputMessage
    }

    Write-Output $returnObject   
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

    Write-Error "Error $actionMessage for Exchange Online distribution group [$Name]. Error: $errorMessage"
    
    $outputMessage = "Invalid | Error $actionMessage for Exchange Online distribution group [$Name]. Error: $errorMessage"
    $returnObject = @{
        text = $outputMessage
    }
}
finally {
    Write-Output $returnObject 
}
#endregion lookup
