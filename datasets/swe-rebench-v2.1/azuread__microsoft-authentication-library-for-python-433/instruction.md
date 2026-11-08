Add public convenience string constants for endpoints of each cloud (sovereign and public)
**Context**
Customers have had difficulty finding the right documentation pages:
https://docs.microsoft.com/en-us/azure/azure-government/documentation-government-developer-guide#endpoint-mapping
https://docs.microsoft.com/en-us/azure/china/resources-developer-guide#check-endpoints-in-azure

**See also other libraries exposing these:**
- [obj-c](https://azuread.github.io/microsoft-authentication-library-for-objc/Enums/MSALAzureCloudInstance.html)
- [.net](https://docs.microsoft.com/en-us/dotnet/api/microsoft.identity.client.azurecloudinstance?view=azure-dotnet)

**Reference:**
https://identitydivision.visualstudio.com/Engineering/_workitems/edit/1063014

**Other:**
https://github.com/AzureAD/microsoft-authentication-library-for-java/issues/258

### Additional contract requirements

- Define the public string constants `AZURE_PUBLIC = "login.microsoftonline.com"`, `AZURE_CHINA = "login.chinacloudapi.cn"`, and `AZURE_US_GOVERNMENT = "login.microsoftonline.us"` in `msal.authority`.
