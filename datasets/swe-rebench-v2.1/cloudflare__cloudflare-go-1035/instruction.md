R2 bucket creation is broken due to API change
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

### Expected output

Able to create R2 bucket

### Actual output

✘ [ERROR] A request to the Cloudflare API (/accounts/<account id>/r2/buckets/bucketname) failed.

  No route matches this url. [code: 10015]

### Steps to reproduce

Attempt to create R2 bucket with API

### References

https://github.com/cloudflare/wrangler2/issues/1654
