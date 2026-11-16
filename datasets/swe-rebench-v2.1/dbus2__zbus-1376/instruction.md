breakage in `zvariant_derive` with `ashpd`
After the latest patch release, `ashpd` no longer compiles. Setting `zvariant_derive = "=5.5.1"` resolves the issue.

Steps to reproduce:
1. `cargo init tmp`
2. `cargo add ashpd`
3. `cargo check`

![Image](https://github.com/user-attachments/assets/98746451-536f-480b-a5a9-caeed11f24df)

### Additional contract requirements

A consumer must be able to derive `SerializeDict` for an empty struct with a dictionary signature and serialize it successfully, without pinning `zvariant_derive` to an older version.
