DuckDNS sub domains do not work
When trying to get a certificate for a subdomain it does not work. It works for wild cards, but not individual subdomains.
It is because of a flawed assumption. See https://plus.google.com/105377443134795862842/posts/YPt1GmJ2gxL for more info.
[HIDDEN]

### Additional contract requirements

- When presenting a challenge for a fully qualified DuckDNS subdomain, the update request must target the registered DuckDNS subdomain, not extra labels used in the challenge domain.
- Cleaning up that challenge must target the same registered DuckDNS subdomain.
- Support for wildcard certificates through DuckDNS must continue to work.
