Refactor host-part matching to strictly follow the spec
https://w3c.github.io/webappsec-csp/#match-hosts

### Additional contract requirements

A source expression whose host part is exactly `*` matches resources from any host.
