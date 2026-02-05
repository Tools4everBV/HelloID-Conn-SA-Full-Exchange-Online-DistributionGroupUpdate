# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Mailbox Management","Exchange Online") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> EntraIdAppId
$tmpName = @'
EntraIdAppId
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> EntraIdCertificatePassword
$tmpName = @'
EntraIdCertificatePassword
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});

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
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});


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
<# Begin: DataSource "exchange-online-distribution-group-permissions | generate-table-mailbox-wildcard" #>
$tmpPsScript = @'
# Warning! When no searchQuery is specified. All mailboxes will be retrieved.
$searchValue = $datasource.searchValue

if ([String]::IsNullOrEmpty($searchValue) -or $searchValue -eq "*") {
    $filter = "*"
}
else {
    $filter = "Name -like '*$searchValue*' -or EmailAddresses -like '*$searchValue*'"
}

# PowerShell commands to import
$commands = @(
    "Get-Mailbox"
    , "Get-EXOMailbox"
    , "Get-EXORecipient"
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

#region Get Mailboxes
try {

    $exchangeQuerySplatParams = @{
        ResultSize = "Unlimited"
    }
    if (-not [string]::IsNullOrEmpty($filter)) {
        $exchangeQuerySplatParams.Add("Filter", $filter)
    }

    Write-Information "Querying distribution groups that match filter [$($exchangeQuerySplatParams.Filter)]"
    $distributionGroups = Get-EXORecipient @exchangeQuerySplatParams | Where-Object { $_.RecipientTypeDetails -eq "MailUniversalDistributionGroup" }

    #Include MailUniversalSecurityGroup -> Only if fully cloud
    #$distributionGroups = Get-EXORecipient @exchangeQuerySplatParams | Where-Object { $_.RecipientTypeDetails -in @("MailUniversalDistributionGroup","MailUniversalSecurityGroup") } 

    $distributionGroups = $distributionGroups | Sort-Object -Property DisplayName
    $resultCount = ($distributionGroups | Measure-Object).Count
    Write-Information "Result count: $resultCount"
    
    if ($resultCount -gt 0) {
        foreach ($distributionGroup in $distributionGroups) {
            Write-Output $distributionGroup
        }
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying distribution groups that match filter [$($exchangeQuerySplatParams.Filter)]. Error Message: $($errorMessage.AuditErrorMessage)"
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
#endregion Get Mailboxes
'@ 
$tmpModel = @'
[{"key":"ExternalDirectoryObjectId","type":0},{"key":"Identity","type":0},{"key":"Alias","type":0},{"key":"EmailAddresses","type":0},{"key":"DisplayName","type":0},{"key":"Name","type":0},{"key":"PrimarySmtpAddress","type":0},{"key":"RecipientType","type":0},{"key":"RecipientTypeDetails","type":0},{"key":"ExchangeVersion","type":0},{"key":"DistinguishedName","type":0},{"key":"OrganizationId","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchValue","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
exchange-online-distribution-group-permissions | generate-table-mailbox-wildcard
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "exchange-online-distribution-group-permissions | generate-table-mailbox-wildcard" #>

<# Begin: DataSource "exchange-online-distribution-group-permissions | group-generate-table-sharedmailbox-left" #>
$tmpPsScript = @'
# PowerShell commands to import
$commands = @(
    "Get-user"
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


#region Get Users
try {
    $properties = @(
        "Id"
        , "Guid"
        , "Name"
        , "DisplayName"
        , "UserPrincipalName"
    )

    $exchangeQuerySplatParams = @{
        Filter     = "*"
        ResultSize = "Unlimited"
    }
    if (-not[String]::IsNullOrEmpty($filter)) {
        $exchangeQuerySplatParams.Add("Filter", $filter)
    }

    Write-Information "Querying users that match filter [$($exchangeQuerySplatParams.Filter)]"
    $users = Get-User @exchangeQuerySplatParams | Select-Object $properties

    $users = $users | Sort-Object -Property Name
    $resultCount = ($users | Measure-Object).Count
    Write-Information "Result count: $resultCount"

    # # Filter out users without name
    # Write-Information "Filtering out users without [name]"
    # $users = $users | Where-Object { -NOT[String]::IsNullOrEmpty($_.name) }
    # $resultCount = ($users | Measure-Object).Count
    # Write-Information "Result count: $resultCount"
    
    if ($resultCount -gt 0) {
        foreach ($user in $users) {
            $displayValue = $user.displayName + " [" + $user.userPrincipalName + "]"
            $returnObject = @{
                displayValue      = $displayValue;
                userPrincipalName = "$($user.userPrincipalName)";
                id                = "$($user.id)";
                guid              = "$($user.guid)";
            }
     
            Write-Output $returnObject
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
    Write-Information "Disconnected from Microsoft Exchange Online"
}
#endregion Get Users
'@ 
$tmpModel = @'
[{"key":"userPrincipalName","type":0},{"key":"id","type":0},{"key":"displayValue","type":0},{"key":"guid","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
exchange-online-distribution-group-permissions | group-generate-table-sharedmailbox-left
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "exchange-online-distribution-group-permissions | group-generate-table-sharedmailbox-left" #>

<# Begin: DataSource "exchange-online-distribution-group-permissions | group-generate-table-sharedmailbox-right" #>
$tmpPsScript = @'
$identity = $datasource.selectedgroup.ExternalDirectoryObjectId
$Permission = $datasource.Permission

# PowerShell commands to import
$commands = @(
    "Get-Mailbox"
    , "Get-EXOMailbox"
    , "Get-User"
    , "Get-DistributionGroupMember"
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

# Get current mailbox permissions
try {
    Write-Information "Getting members of distribution group [$identity]"

    $members = Get-DistributionGroupMember -Identity $identity -ResultSize Unlimited

    $users = foreach ($member in $members) {
        # Alleen echte users ophalen (skip contacts/groups)
        if ($member.RecipientTypeDetails -eq 'UserMailbox') {
            Get-User -Identity $member.Identity -ErrorAction SilentlyContinue
        }
    }

    $users = $users | Sort-Object DisplayName

    foreach ($user in $users) {
        $displayValue = "$($user.DisplayName) [$($user.UserPrincipalName)]"

        Write-Output @{
            displayValue      = $displayValue
            userPrincipalName = $user.UserPrincipalName
            id                = $user.Id
            guid              = $user.Guid
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
    Write-Information "Disconnected from Microsoft Exchange Online"
}
'@ 
$tmpModel = @'
[{"key":"userPrincipalName","type":0},{"key":"id","type":0},{"key":"displayValue","type":0},{"key":"guid","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"selectedGroup","type":0,"options":1}]
'@ 
$dataSourceGuid_2 = [PSCustomObject]@{} 
$dataSourceGuid_2_Name = @'
exchange-online-distribution-group-permissions | group-generate-table-sharedmailbox-right
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_2_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_2) 
<# End: DataSource "exchange-online-distribution-group-permissions | group-generate-table-sharedmailbox-right" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Exchange online - Distribution Group - Manage permissions" #>
$tmpSchema = @"
[{"label":"Details","fields":[{"templateOptions":{"title":"Retrieving this information from Exchange takes an average of +/- 10 seconds. Please wait while the data is loaded.","titleField":"","bannerType":"Info","useBody":false},"type":"textbanner","summaryVisibility":"Hide element","body":"Text Banner Content","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"searchGroup","templateOptions":{"label":"Search","placeholder":""},"type":"input","summaryVisibility":"Hide element","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"gridGroup","templateOptions":{"label":"Distribution group","required":true,"grid":{"columns":[{"headerName":"Display Name","field":"DisplayName"},{"headerName":"Primary Smtp Address","field":"PrimarySmtpAddress"},{"headerName":"Recipient Type","field":"RecipientType"},{"headerName":"Guid","field":"ExternalDirectoryObjectId"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchValue","otherFieldValue":{"otherFieldKey":"searchGroup"}}]}},"useDefault":false,"allowCsvDownload":true},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Group Permissions","fields":[{"templateOptions":{"title":"Retrieving this information from Exchange takes an average of +/- 30 seconds. Please wait while the data is loaded.","titleField":"","bannerType":"Info","useBody":false},"type":"textbanner","summaryVisibility":"Hide element","body":"Text Banner Content","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"permissionList","templateOptions":{"label":"Distribution group permissions","required":false,"filterable":true,"useDataSource":true,"dualList":{"options":[{"guid":"75ea2890-88f8-4851-b202-626123054e14","Name":"Apple"},{"guid":"0607270d-83e2-4574-9894-0b70011b663f","Name":"Pear"},{"guid":"1ef6fe01-3095-4614-a6db-7c8cd416ae3b","Name":"Orange"}],"optionKeyProperty":"guid","optionDisplayProperty":"displayValue"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[]}},"destinationDataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_2","input":{"propertyInputs":[{"propertyName":"selectedGroup","otherFieldValue":{"otherFieldKey":"gridGroup"}}]}}},"hideExpression":"!model[\"searchGroup\"]","type":"duallist","summaryVisibility":"Show","sourceDataSourceIdentifierSuffix":"source-datasource","destinationDataSourceIdentifierSuffix":"destination-datasource","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Exchange online - Distribution Group - Manage permissions
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
Exchange online - Distribution Group - Manage permissions
'@
$tmpTask = @'
{"name":"Exchange online - Distribution Group - Manage permissions","script":"$identity = $form.gridGroup.ExternalDirectoryObjectId\r\n$usersToAdd = $form.permissionList.leftToRight\r\n$usersToRemove = $form.permissionList.rightToLeft\r\n\r\n# PowerShell commands to import\r\n$commands = @(\r\n    \"Get-EXORecipient\",\r\n    \"Add-DistributionGroupMember\",\r\n    \"Remove-DistributionGroupMember\"\r\n)\r\n\r\n# Set TLS to accept TLS, TLS 1.1 and TLS 1.2\r\n[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12\r\n\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n#region functions\r\nfunction Resolve-HTTPError {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $httpErrorObj = [PSCustomObject]@{\r\n            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId\r\n            MyCommand             = $ErrorObject.InvocationInfo.MyCommand\r\n            RequestUri            = $ErrorObject.TargetObject.RequestUri\r\n            ScriptStackTrace      = $ErrorObject.ScriptStackTrace\r\n            ErrorMessage          = ''\r\n        }\r\n\r\n        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {\r\n            # $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message # Does not show the correct error message for the Raet IAM API calls\r\n            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message\r\n\r\n        }\r\n        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {\r\n            $httpErrorObj.ErrorMessage = [HelloID.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\r\n        }\r\n\r\n        Write-Output $httpErrorObj\r\n    }\r\n}\r\n\r\nfunction Get-ErrorMessage {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $errorMessage = [PSCustomObject]@{\r\n            VerboseErrorMessage = $null\r\n            AuditErrorMessage   = $null\r\n        }\r\n\r\n        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject\r\n\r\n            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage\r\n\r\n            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage\r\n        }\r\n\r\n        # If error message empty, fall back on $ex.Exception.Message\r\n        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {\r\n            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message\r\n        }\r\n        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {\r\n            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message\r\n        }\r\n\r\n        Write-Output $errorMessage\r\n    }\r\n}\r\n\r\nfunction Get-MSEntraCertificate {\r\n    [CmdletBinding()]\r\n    param()\r\n    try {\r\n        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)\r\n        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)\r\n        Write-Output $certificate\r\n    }\r\n    catch {\r\n        $PSCmdlet.ThrowTerminatingError($_)\r\n    }\r\n}\r\n#endregion functions\r\n\r\n#region Import module & connect\r\ntry {    \r\n    $actionMessage = \"importing module [ExchangeOnlineManagement]\"\r\n    $importModuleSplatParams = @{\r\n        Name        = \"ExchangeOnlineManagement\"\r\n        Cmdlet      = $commands\r\n        Verbose     = $false\r\n        ErrorAction = \"Stop\"\r\n    }\r\n    $null = Import-Module @importModuleSplatParams\r\n\r\n    #region Retrieving certificate\r\n    $actionMessage = \"retrieving certificate\"\r\n    $certificate = Get-MSEntraCertificate\r\n    #endregion Retrieving certificate\r\n    \r\n    #region Connect to Microsoft Exchange Online\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/connect-exchangeonline?view=exchange-ps\r\n    $actionMessage = \"connecting to Microsoft Exchange Online\"\r\n    $createExchangeSessionSplatParams = @{\r\n        Organization          = $EntraIdOrganization\r\n        AppID                 = $EntraIdAppId\r\n        Certificate           = $certificate\r\n        CommandName           = $commands\r\n        ShowBanner            = $false\r\n        ShowProgress          = $false\r\n        TrackPerformance      = $false\r\n        SkipLoadingCmdletHelp = $true\r\n        SkipLoadingFormatData = $true\r\n        ErrorAction           = \"Stop\"\r\n    }\r\n    $null = Connect-ExchangeOnline @createExchangeSessionSplatParams\r\n    Write-Information \"Connected to Microsoft Exchange Online\"\r\n} \r\ncatch {\r\n    $ex = $PSItem\r\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"        \r\n    }\r\n    else {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    }\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n}\r\n\r\n#region Get Distributiongroup\r\ntry {\r\n    $exchangeQuerySplatParams = @{\r\n        Identity    = $identity\r\n        ErrorAction = \"Stop\"\r\n    }\r\n\r\n    Write-Information \"Querying distribution group with identity [$identity]\"\r\n    $Group = Get-EXORecipient @exchangeQuerySplatParams\r\n\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n    }\r\n    else {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    }\r\n    $log = @{\r\n        Action            = \"undefined\" # optional. ENUM (undefined = default) \r\n        System            = \"ExchangeOnline\" # optional (free format text) \r\n        Message           = $auditMessage # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = \"$($form.gridGroup.DisplayName)\" # optional (free format text) \r\n        TargetIdentifier  = \"$($form.gridGroup.ExternalDirectoryObjectId)\" # optional (free format text) \r\n    }\r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n    exit # use when using multiple try/catch and the script must stop\r\n}\r\n#endregion Get Distributiongroup\r\n\r\n\r\n#region Grant selected users to distribution group\r\nforeach ($userToAdd in $usersToAdd) {\r\n    try {\r\n        Write-Verbose \"Granting access to distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToAdd.UserPrincipalName) ($($userToAdd.guid))]\"\r\n\r\n        $addMemberSplatParams = @{\r\n            Identity    = $group.ExternalDirectoryObjectId\r\n            Member      = $userToAdd.Guid\r\n            ErrorAction = \"SilentlyContinue\"\r\n        }\r\n\r\n        $null = Add-DistributionGroupMember @addMemberSplatParams\r\n\r\n        Write-Information \"Successfully granted access to distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToAdd.UserPrincipalName) ($($userToAdd.guid))]\"\r\n\r\n        # Audit log for HelloID\r\n        $Log = @{\r\n            Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n            System            = \"Exchange\" # optional (free format text) \r\n            Message           = \"Successfully granted access to distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToAdd.UserPrincipalName) ($($userToAdd.guid))]\" # required (free format text) \r\n            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $group.DisplayName # optional (free format text)\r\n            TargetIdentifier  = $([string]$group.ExternalDirectoryObjectId) # optional (free format text)\r\n        }\r\n        #send result back\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n    }\r\n    catch {\r\n        $ex = $PSItem\r\n        if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n            $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n            $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n        }\r\n        else {\r\n            $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n            $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n        }\r\n        $log = @{\r\n            Action            = \"undefined\" # optional. ENUM (undefined = default) \r\n            System            = \"ExchangeOnline\" # optional (free format text) \r\n            Message           = $auditMessage # required (free format text) \r\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = \"$($userToAdd.displayValue)\" # optional (free format text) \r\n            TargetIdentifier  = \"$($userToAdd.guid)\" # optional (free format text) \r\n        }\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n        Write-Warning $warningMessage\r\n        Write-Error $auditMessage\r\n        # exit # use when using multiple try/catch and the script must stop\r\n    }\r\n}\r\n\r\n#region Revoke selected users from distribution group\r\nforeach ($userToRemove in $usersToRemove) {\r\n    try {\r\n        Write-Verbose \"Revoking permission from distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToRemove.UserPrincipalName) ($($userToRemove.guid))]\"\r\n\r\n        $removeMemberSplatParams = @{\r\n            Identity    = $group.ExternalDirectoryObjectId\r\n            Member      = $userToRemove.Guid\r\n            Confirm     = $false\r\n            ErrorAction = \"SilentlyContinue\"\r\n        }\r\n\r\n        $null = Remove-DistributionGroupMember @removeMemberSplatParams\r\n\r\n        Write-Information \"Successfully revoked permission from distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToRemove.UserPrincipalName) ($($userToRemove.guid))]\"\r\n\r\n        # Audit log for HelloID\r\n        $Log = @{\r\n            Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n            System            = \"Exchange\" # optional (free format text) \r\n            Message           = \"Successfully revoked permission from distributiongroup [$($group.DisplayName) ($($group.ExternalDirectoryObjectId))] for user [$($userToRemove.UserPrincipalName) ($($userToRemove.guid))]\" # required (free format text) \r\n            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $group.DisplayName # optional (free format text)\r\n            TargetIdentifier  = $([string]$group.ExternalDirectoryObjectId) # optional (free format text)\r\n        }\r\n        #send result back\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n    }\r\n    catch {\r\n        $ex = $PSItem\r\n        if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n            $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n            $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n        }\r\n        else {\r\n            $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n            $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n        }\r\n        $log = @{\r\n            Action            = \"undefined\" # optional. ENUM (undefined = default) \r\n            System            = \"ExchangeOnline\" # optional (free format text) \r\n            Message           = $auditMessage # required (free format text) \r\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = \"$($userToRemove.displayValue)\" # optional (free format text) \r\n            TargetIdentifier  = \"$($userToRemove.guid)\" # optional (free format text) \r\n        }\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n        Write-Warning $warningMessage\r\n        Write-Error $auditMessage\r\n        # exit # use when using multiple try/catch and the script must stop\r\n    }\r\n}\r\n\r\n#Remove Exchange session\r\n# Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/disconnect-exchangeonline?view=exchange-ps\r\n$deleteExchangeSessionSplatParams = @{\r\n    Confirm     = $false\r\n    ErrorAction = \"Stop\"\r\n}\r\n$null = Disconnect-ExchangeOnline @deleteExchangeSessionSplatParams\r\nWrite-Information \"Disconnected from Microsoft Exchange Online\"\r\n","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-pencil-square" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

