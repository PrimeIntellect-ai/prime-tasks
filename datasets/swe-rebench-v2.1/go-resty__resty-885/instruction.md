Support query parameters without encoding
When calling the SetQueryParam method, the request request will encode the query in the URL, for example: registry=nacos://test:6801, which will be encoded as: registry=nacos%3A%2F%2Ftest%3A6801; is there any way? To set query parameters without encoding, for example: SetQueryEscape(false)

### Additional contract requirements

Requests can opt out of percent-encoding query parameter values using `Request.SetUnescapeQueryParams(true)`. In this mode, characters such as `:` and `/` remain literal in the request URL, and the request conveys the original parameter values.
