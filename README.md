# HelloID-Conn-SA-Full-Exchange-Online-DistributionGroupUpdate

| :information_source: Information |
| :------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description
HelloID-Conn-SA-Full-ExchangeOnline-DistributionGroupUpdate is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

With this delegated form you can search for a distribution group or a mail-enabled security group and update its core properties in Exchange Online. The form implements the flow defined in the provided script (All-in-one setup/createform.ps1):
 1. Search and select the distribution group or mail-enabled security group (wildcard search supported)
 2. Edit the group’s `Name`, `Alias`, and `PrimarySmtpAddress`
 3. Validate the changes against Entra ID (for better performance)
 4. Submit the form to apply the updates in Exchange Online

Notes shown in the form:
- Retrieving groups typically takes ~10 seconds
- Validation typically takes ~10 seconds

## Getting started
### Requirements

#### App Registration & Certificate Setup

Before implementing this connector, make sure to configure a Microsoft Entra ID, an App Registration. During the setup process, you’ll create a new App Registration in the Entra portal, assign the necessary API permissions (such as user and group read/write), and generate and assign a certificate.

Follow the official Microsoft documentation for creating an App Registration and setting up certificate-based authentication:
- [App-only authentication with certificate (Exchange Online)](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps#set-up-app-only-authentication)

#### HelloID-specific configuration

Once you have completed the Microsoft setup and followed their best practices, configure the following HelloID-specific requirements.

- **Exchange Online app-only access:**
  - Configure app-only authentication as described in Microsoft’s documentation (application access policy as needed for scoping).
- **Entra ID Role assignment:**
  - Assign the **Exchange Recipient Administrator** (or appropriate Exchange administrative) role to the App Registration.
- **Certificate:**
  - Upload the public key file (.cer) in Entra ID.
  - Provide the certificate as a Base64 string in HelloID. For instructions on creating the certificate and obtaining the base64 string, refer to our forum post: [Setting up a certificate for Microsoft Graph API in HelloID connectors](https://forum.helloid.com/forum/helloid-provisioning/5338-instruction-setting-up-a-certificate-for-microsoft-graph-api-in-helloid-connectors#post5338)

### Connection settings

The following user-defined variables are used by the connector and referenced by the script:

| Setting                        | Description                                               | Mandatory |
| ------------------------------ | --------------------------------------------------------- | --------- |
| EntraIdOrganization            | Entra tenant organization (e.g., contoso.onmicrosoft.com) | Yes       |
| EntraIdAppId                   | Entra application (client) ID                             | Yes       |
| EntraIdCertificateBase64String | Base64-encoded certificate string                         | Yes       |
| EntraIdCertificatePassword     | Certificate password                                      | Yes       |

## Remarks

- Group search:
  - When no search value or `*` is provided, all distribution groups are retrieved.
- Update scope:
  - The form updates `Name`, `Alias`, and `PrimarySmtpAddress` of the selected distribution group.
- Validation step:
  - Input is validated against current group data to prevent conflicts before submission.
- Performance notes:
  - Retrieving groups typically takes ~10 seconds; validation typically takes ~10 seconds.
- Duplicate import:
  - When importing a duplicate form, resource names can be suffixed automatically, as configured in the script.

## Development resources

### API endpoints

This connector uses Exchange Online PowerShell (EXO) cmdlets via the `ExchangeOnlineManagement` module:

| Cmdlet/Operation           | Description                                             |
| -------------------------- | ------------------------------------------------------- |
| Connect-ExchangeOnline     | Connect to Exchange Online using app-only certificate  |
| Get-DistributionGroup      | Search and retrieve distribution groups                |
| Set-DistributionGroup      | Update distribution group properties                   |
| Disconnect-ExchangeOnline  | Disconnect the Exchange Online session                 |

### API documentation

- Exchange Online PowerShell overview: https://learn.microsoft.com/powershell/exchange/exchange-online-powershell
- Connect to Exchange Online: https://learn.microsoft.com/powershell/module/exchange/connect-exchangeonline
- Get-DistributionGroup: https://learn.microsoft.com/powershell/module/exchange/get-distributiongroup
- Set-DistributionGroup: https://learn.microsoft.com/powershell/module/exchange/set-distributiongroup
- Disconnect-ExchangeOnline: https://learn.microsoft.com/powershell/module/exchange/disconnect-exchangeonline

## Getting help
> :bulb: **Tip:**  
> For more information on Delegated Forms, please refer to our documentation pages: https://docs.helloid.com/en/service-automation/delegated-forms.html

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
