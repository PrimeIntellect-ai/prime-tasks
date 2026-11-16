HttpRequestMetaData scheme case sensitivity
`HttpRequestMetaData#scheme()` javadocs state the result will be lowercase, but this is not always the case. `DefaultMultiAddressUrlHttpClientBuilder` has a few instances (`CachingKeyFactory`, `UrlKey`) which rely upon the lowercase behavior describe in `HttpRequestMetaData#scheme()`. In general the comparisons should be done in a case insensitive fashion [1].

[1] https://tools.ietf.org/html/rfc3986#section-3.1
> Although schemes are case-
   insensitive, the canonical form is lowercase and documents that
   specify schemes must do so with lowercase letters.  An implementation
   should accept uppercase letters as equivalent to lowercase in scheme
   names (e.g., allow "HTTP" as well as "http") for the sake of
   robustness but should only produce lowercase scheme names for
   consistency.

original context: https://github.com/apple/servicetalk/pull/1387#discussion_r589684620
