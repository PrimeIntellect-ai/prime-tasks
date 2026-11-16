Default values for properties in a bundle overridden by API app
**Describe the bug**
Admin sets default value for Workspace property to be applied for any workspace creation in a bundle
When trying to create it default value is empty

**Steps to reproduce**

1. Update default value in bundle temple.json and build/register bundle
1. Try to create the workspace default is not set
1. Code merging props overrides it https://github.com/microsoft/AzureTRE/blob/main/api_app/services/schema_service.py#L28-L30
