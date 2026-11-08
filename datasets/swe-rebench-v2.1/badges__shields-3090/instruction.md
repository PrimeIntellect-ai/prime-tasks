Harmonize cache param name: maxAge -> cacheSeconds
The cache control parameter has long been `?maxAge`. I'd like to change this to `?cacheSeconds` for consistency with the Endpoint badge.

The reason I used "cache seconds" on the endpoint badge is that it's more colloquial and understandable. We also set a few cache directives, not just `Cache-Control: max-age` so I think it's better not to use that name.

This could look similar to the change @mbarkhau just implemented for the color params: #3012
