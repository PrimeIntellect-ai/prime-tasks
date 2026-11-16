Add flag HTML_NOOPENER_LINKS to create absolute links with "noopener" rel attribute
There are already the following flags that add a certain value to the "rel" attribute of absolute links:
* HTML_NOREFERRER_LINKS: "noreferrer"
* HTML_NOFOLLOW_LINKS: "nofollow"

At least for the following reasons it would be desirable to have a flag that also adds a "noopener" value to the "rel" attribute:
* Security: see [About rel=noopener](https://mathiasbynens.github.io/rel-noopener/)
* Performance: see [The performance benefits of rel=noopener](https://jakearchibald.com/2016/performance-benefits-of-rel-noopener/)

The request is to add the flag HTML_NOOPENER_LINKS that implements this.

### Additional contract requirements

- When `HTML_NOFOLLOW_LINKS`, `HTML_NOREFERRER_LINKS`, and `HTML_NOOPENER_LINKS` are all enabled, absolute links must have `rel="nofollow noreferrer noopener"`.
