Add attribution_domains attribute to Account
According to [Trunks & Tidbits January 2025](https://blog.joinmastodon.org/2025/02/trunk-tidbits-january-2025/), an `attributions_domains` attribute has been added to `Account`. See https://docs.joinmastodon.org/entities/Account/#attribution_domains

### Additional contract requirements

- Use `attribution_domains` as the JSON attribute name and expose its value as `CredentialAccount.attributionDomains`, a `List<String>`.
