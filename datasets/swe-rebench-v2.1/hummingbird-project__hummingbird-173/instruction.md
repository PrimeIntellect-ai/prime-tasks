Feature: Associate a unique ID with each request
Vapor keeps a unique ID for each request which, although not publicly exposed yet, allows us to track logs related to a specific request. I think that this kind of information could also be useful for logs originating from a handled Hummingbird Request.

Related: https://github.com/vapor/vapor/pull/2964

### Additional contract requirements

Expose each request's associated unique identifier to request-handling code through a public `HBRequest.id` accessor, so it can be used to correlate information with the request.
