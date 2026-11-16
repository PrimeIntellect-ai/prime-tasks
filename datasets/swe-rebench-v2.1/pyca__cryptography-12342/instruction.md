load_ssh_private_key() does not have unsafe_skip_rsa_key_validation (like load_pem_private_key())
Importing RSA private keys is relatively slow due to the RSA key validation happening.

The load_pem_private_key() allows to disable RSA validation with the unsafe_skip_rsa_key_validation parameter. This option does not exist in load_ssh_private_key().

It would be nice to have the same feature for load_ssh_private_key().

### Additional contract requirements

- `load_ssh_private_key` accepts a keyword-only argument named
  `unsafe_skip_rsa_key_validation` that defaults to `False`.
- When `unsafe_skip_rsa_key_validation` is `True`, RSA private keys are loaded
  without the expensive structural validation that is otherwise performed. A
  structurally invalid RSA private key that is rejected when the argument is
  `False` loads successfully when the argument is `True`.
- Passing a value that is not a boolean for `unsafe_skip_rsa_key_validation`
  raises `TypeError`.


- - When `unsafe_skip_rsa_key_validation` is `False`, a structurally invalid RSA private key raises `ValueError`.
