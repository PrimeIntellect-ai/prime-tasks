Options for lookup_key
Hi - I wanted to add a new lookup key provider (for Azure Key Vault). I've created the function in the provider package but the `options` map is empty when the function is called. Is this functionality implemented yet?

```go
func AzureKeyVaultLookupKey(c hieraapi.ProviderContext, key string, options map[string]px.Value) px.Value {
	vaultName, ok := options[`vault_name`]
	if !ok {
		panic(px.Error(hieraapi.MissingRequiredOption, issue.H{`option`: `vault_name`}))
	}
```

When running this always fails with Missing required provider option 'vault_name'

The hiera.yaml is

```yaml
---
version: 5
defaults:
  datadir: data
  data_hash: yaml_data
hierarchy:
  - name: secret
    lookup_key: azure_key_vault
    options:
      vault_name: xxx
```
