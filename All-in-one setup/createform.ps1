# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Exchange Online") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> EntraIdCertificatePassword
$tmpName = @'
EntraIdCertificatePassword
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> EntraIdAppId
$tmpName = @'
EntraIdAppId
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #3 >> EntraIdOrganization
$tmpName = @'
EntraIdOrganization
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #4 >> EntraIdCertificateBase64String
$tmpName = @'
EntraIdCertificateBase64String
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}

        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
	Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "Exchange-online-distribution-group-update | Generate-table-update" #>
$tmpPsScript = @'
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
'@ 
$tmpModel = @'
[{"key":"Alias","type":0},{"key":"name","type":0},{"key":"id","type":0},{"key":"primarySmtpAddress","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchValue","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
Exchange-online-distribution-group-update | Generate-table-update
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "Exchange-online-distribution-group-update | Generate-table-update" #>

<# Begin: DataSource "Exchange-online-distribution-group-update | function-check-online-group-exists" #>
$tmpPsScript = @'
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
'@ 
$tmpModel = @'
[{"key":"text","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"Name","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"PrimarySmtpAddress","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"Alias","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"SelectedSM","type":0,"options":1}]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
Exchange-online-distribution-group-update | function-check-online-group-exists
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "Exchange-online-distribution-group-update | function-check-online-group-exists" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Exchange online - Distribution Group - Update" #>
$tmpSchema = @"
[{"label":"Search Group","fields":[{"templateOptions":{"title":"Retrieving this information from Exchange Online takes an average of +/- 10 seconds.","titleField":"","bannerType":"Info","useBody":true},"type":"textbanner","summaryVisibility":"Show","body":"Please wait so we can retreive the input.","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"searchfield","templateOptions":{"label":"Search","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"distributionGroup","templateOptions":{"label":"Distribution groups","required":true,"grid":{"columns":[{"headerName":"Name","field":"name"},{"headerName":"Alias","field":"Alias"},{"headerName":"Primary Smtp Address","field":"primarySmtpAddress"},{"headerName":"Id","field":"id"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchValue","otherFieldValue":{"otherFieldKey":"searchfield"}}]}},"useFilter":true,"useDefault":false,"searchPlaceHolder":"Search this data","allowCsvDownload":true},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Edit Group","fields":[{"templateOptions":{"title":"Retrieving this information from Exchange Online takes an average of +/- 10 seconds.","titleField":"","bannerType":"Info","useBody":true},"type":"textbanner","summaryVisibility":"Show","body":"Please wait so we can validate the input.","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"name","templateOptions":{"label":"name","placeholder":"","required":true,"minLength":2,"useDependOn":true,"dependOn":"distributionGroup","dependOnProperty":"name"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"alias","templateOptions":{"label":"Alias","useDependOn":true,"dependOn":"distributionGroup","dependOnProperty":"Alias","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"primarySmtpAddress","templateOptions":{"label":"PrimarySmtpAddress","useDependOn":true,"dependOn":"distributionGroup","dependOnProperty":"primarySmtpAddress","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"Validation","templateOptions":{"label":"Validate","readonly":true,"useDataSource":true,"pattern":"^Valid.*","dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[{"propertyName":"Name","otherFieldValue":{"otherFieldKey":"name"}},{"propertyName":"PrimarySmtpAddress","otherFieldValue":{"otherFieldKey":"primarySmtpAddress"}},{"propertyName":"Alias","otherFieldValue":{"otherFieldKey":"alias"}},{"propertyName":"SelectedSM","otherFieldValue":{"otherFieldKey":"searchfield"}}]}},"displayField":"text","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Exchange online - Distribution Group - Update
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null} 
$delegatedFormName = @'
Exchange online - Distribution Group - Update
'@
$tmpTask = @'
{"name":"Exchange online - Distribution Group - Update","script":"# Enable TLS1.2\n[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12\n\n$VerbosePreference = \"SilentlyContinue\"\n$InformationPreference = \"Continue\"\n$WarningPreference = \"Continue\"\n\n# variables configured in form:\n$exchangeDGGUID = $form.distributionGroup.id\n$name = $form.name\n$alias = $form.alias\n$primarySmtpAddress = $form.primarySmtpAddress\n\n# PowerShell commands to import\n$commands = @(\"Get-DistributionGroup\", \"Set-DistributionGroup\")\n#endregion init\n\n#region functions\n\n#endregion functions\n\nfunction Get-MSEntraCertificate {\n    [CmdletBinding()]\n    param()\n    try {\n        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)\n        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)\n        Write-Output $certificate\n    }\n    catch {\n        $PSCmdlet.ThrowTerminatingError($_)\n    }\n}\n\n#region Import module & connect\ntry {    \n    $actionMessage = \"importing module [ExchangeOnlineManagement]\"\n    $importModuleSplatParams = @{\n        Name        = \"ExchangeOnlineManagement\"\n        Verbose     = $false\n        ErrorAction = \"Stop\"\n    }\n    $null = Import-Module @importModuleSplatParams\n\n    #region Retrieving certificate\n    $actionMessage = \"retrieving certificate\"\n    $certificate = Get-MSEntraCertificate\n    #endregion Retrieving certificate\n    \n    #region Connect to Microsoft Exchange Online\n    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/connect-exchangeonline?view=exchange-ps\n    $actionMessage = \"connecting to Microsoft Exchange Online\"\n    $createExchangeSessionSplatParams = @{\n        Organization          = $EntraIdOrganization\n        AppID                 = $EntraIdAppId\n        Certificate           = $certificate\n        CommandName           = $commands\n        ShowBanner            = $false\n        ShowProgress          = $false\n        TrackPerformance      = $false\n        SkipLoadingCmdletHelp = $true\n        SkipLoadingFormatData = $true\n        ErrorAction           = \"Stop\"\n    }\n    $null = Connect-ExchangeOnline @createExchangeSessionSplatParams\n    Write-Information \"Connected to Microsoft Exchange Online\"\n} \ncatch {\n    $ex = $PSItem\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"        \n    }\n    else {\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\n    }\n    Write-Warning $warningMessage\n    Write-Error $auditMessage\n}\n\n\n\n#region get distribution group\ntry{\n    $GetDistributionGroupParams = @{\n        Identity    = $exchangeDGGUID\n        ErrorAction = 'Stop'\n    }\n\n    $distributionGroup = Get-DistributionGroup @GetDistributionGroupParams\n    $currentAddresses = $distributionGroup.EmailAddresses\n    $proxyAddresses = @()\n    foreach ($address in $currentAddresses) {\n        if ($address.StartsWith('SMTP:')) {\n            $address = $address -replace 'SMTP:', 'smtp:'\n        }\n        if ($address -ne \"smtp:\" + $primarySmtpAddress) {\n            $proxyAddresses += $address\n        }\n    }\n\n    # Set new primary SMTP as uppercase 'SMTP:' and keep other proxies as lowercase 'smtp:'\n    $proxyAddresses += 'SMTP:' + $primarySmtpAddress\n\n    #region update distribution group\n    $actionMessage = \"updating distribution group\"\n\n    $UpdateDistributionGroupParams = @{\n        Identity       = $exchangeDGGUID\n        DisplayName    = $name\n        Name           = $name\n        EmailAddresses = $proxyAddresses\n        Alias          = $alias\n        ErrorAction    = 'Stop'\n    }\n\n    Set-DistributionGroup @UpdateDistributionGroupParams\n \n    Write-Information  \"Distribution Group [$name] updated successfully\" \n    $Log = @{\n        Action            = \"UpdateResource\" # optional. ENUM (undefined = default) \n        System            = \"Exchange Online\" # optional (free format text) \n        Message           = \"Distribution Group [$name] updated successfully\"  # required (free format text) \n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \n        TargetDisplayName = $name # optional (free format text) \n        TargetIdentifier  = $([string]$exchangeDGGUID) # optional (free format text) \n    }\n    #send result back  \n    Write-Information -Tags \"Audit\" -MessageData $log \n}\ncatch {\n    $ex = $PSItem\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\n    }\n    else {\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\n    }\n   $Log = @{\n        Action            = \"UpdateResource\" # optional. ENUM (undefined = default) \n        System            = \"Exchange Online\" # optional (free format text) \n        Message           = \"Error $actionMessage for Exchange Online distribution group [$name]\" # required (free format text) \n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \n        TargetDisplayName = $name # optional (free format text) \n        TargetIdentifier  = $([string]$exchangeDGGUID) # optional (free format text) \n    }\n    Write-Information -Tags \"Audit\" -MessageData $log\n    Write-Warning $warningMessage\n    Write-Error $auditMessage\n    # exit # use when using multiple try/catch and the script must stop\n}\nfinally {\n    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/disconnect-exchangeonline?view=exchange-ps\n    $deleteExchangeSessionSplatParams = @{\n        Confirm     = $false\n        ErrorAction = \"Stop\"\n    }\n    $null = Disconnect-ExchangeOnline @deleteExchangeSessionSplatParams\n    Write-Information \"Disconnected from Microsoft Exchange Online\"\n}","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-users" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

