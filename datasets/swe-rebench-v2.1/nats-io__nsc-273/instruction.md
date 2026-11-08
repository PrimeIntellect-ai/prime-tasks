adding user with a public key doesn't check if it already stores the private key - so creds creation fails.
If the key exists (created `nsc generate nkey --store`)
