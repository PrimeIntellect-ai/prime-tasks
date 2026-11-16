Possible false positive with sensitive-in-attribute check
**Describe the bug**
When the `private_key_format` attribute is set in a `vault_pki_secret_backend_cert` resource for the Hashicorp Vault provider, the attribute is flagged as a sensitive-in-attribute finding

**To Reproduce**
```
provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

resource "vault_pki_secret_backend_cert" "server_cert" {
  backend     = var.vault_backend
  name        = var.vault_name
  common_name = var.server_name
  format = "pem"
  # this line is flagged
  private_key_format = "pkcs8"
}
```

**Expected behavior**
This shouldn't be a finding. The check refers to placing secrets in attributes whereas `private_key_format` defines the output format only.


**Additional context**
tfsec version 0.63.1
