Add support for RFC5861 Cache-Control headers
[RFC5861](https://datatracker.ietf.org/doc/html/rfc5861) standardised two Cache-Control extensions:
1. `stale-while-revalidate`
2. `stale-if-error`

Please add support for these in the standard werkzerg `ResponseCacheControl`.

One use case of these extensions is to allow sites to have their CDNs "coalesce" requests for content when it goes stale.  Another is to serve a stale representation from the CDN when the site is having an outage.  It's possible to solve this problem without changes to werkzeug, but as it's a standard feature, I think it would be nice to have it in the library.

### Additional contract requirements

Add a public property `stale_while_revalidate` on `ResponseCacheControl` that returns the integer value of the `stale-while-revalidate` directive when it is present in the header, and `None` when it is absent.

Add a public property `stale_if_error` on `ResponseCacheControl` that returns the integer value of the `stale-if-error` directive when it is present in the header, and `None` when it is absent.
