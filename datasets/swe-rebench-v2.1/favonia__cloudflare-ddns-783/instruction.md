Add Cloudflare comments to updated records
Would be cool if we could add text to the Cloudflare comment field for the updated record.
Preferable if the comment can be personalised.

### Additional contract requirements

- The DNS record creation operation takes the record comment as its final argument: `CreateRecord(ctx context.Context, ppfmt pp.PP, domain domain.Domain, ipNet ipnet.Type, ip netip.Addr, ttl api.TTL, proxied bool, recordComment string) (string, bool)` in package `internal/api`. The created record's comment field is set to the supplied `recordComment`; the string may be empty.
- The record-setting operation takes the record comment as its final argument: `Set(ctx context.Context, ppfmt pp.PP, domain domain.Domain, ipNet ipnet.Type, ip netip.Addr, ttl api.TTL, proxied bool, recordComment string) setter.ResponseCode` in package `internal/setter`. When it creates a new record, the supplied `recordComment` is used for that record.
- The configuration exposes the comment as the `RecordComment` string field of `Config` in package `internal/config`, read from the environment variable `RECORD_COMMENT`; its default value is the empty string.
- The configuration output includes a `Record comment:` item. An empty comment is displayed as `(empty)`; the comment `Created by Cloudflare DDNS` is displayed as `"Created by Cloudflare DDNS"`.
