CookieJar.setCookie does not slide expiration for set-cookie headers with max-age
The creation time from old-cookie is carried forward per the spec, but this causes the expiryTime() to be unaffected by subsequent set-cookie headers, so the cookie will expire when its creation + max-age > now, even if subsequent set-cookie headers specified max-age with the intent of making the expiration now + max-age.

I'm currently working around this by just having a Store implementation that passes `null` to the callback, so that the creation is not carried forward.
CookieJar.setCookie does not slide expiration for set-cookie headers with max-age
              > My reading of RFC6265 is that `expiry-time` and `creation-time` are two distinct fields (Section 5.3), and `creation-time` is not used for expiration at all. Steps 5.3.2 and 5.3.11.3 cover `creation-time` and `expiry-time` is covered by 5.3.3, and sections 5.2.1 and 5.2.2.

As far as I can tell, this issue still exists, assuming my past interpretation of RFC6265 was correct.

_Originally posted by @VelynM in https://github.com/salesforce/tough-cookie/issues/154#issuecomment-1839869846_
