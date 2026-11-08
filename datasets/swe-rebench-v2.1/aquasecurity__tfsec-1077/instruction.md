Azure default_action_deny_rule missing important configuration issues
**Describe the bug**
The logic used in `internal/app/tfsec/rules/azure/storage/default_action_deny_rule.go` is missing security checks for the default_action option. The logic assumes that there is always going to be a `azurerm_storage_account_network_rules` block and therefor does not have any enforcement to the `azurerm_storage_account` `network_rules.default_action`

**To Reproduce**
Run against an azure `storage_accounts.tf` file
```
resource "azurerm_storage_account" "test" {
  name                      = "test"
  resource_group_name       = azurerm_resource_group.test
  location                  = azurerm_resource_group.test
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"
}
```

**Expected behavior**
A critical error when there is no `default_action` or `network_rules.default_action`

**Screenshots**

**Desktop (please complete the following information):**
 - OS: MacOS

**Additional context**
