Support report-to directive
Add support for [`report-to`](http://w3c.github.io/webappsec-csp/#directive-report-to) directive.

### Additional contract requirements

- The `report-to` directive must contain exactly one token. If it contains no token or more than one token, the parser reports the error notice `The report-to directive must contain exactly one token`.
- A policy that contains a `report-to` directive cannot be merged with another policy: calling `intersect` or `union` throws `IllegalArgumentException` with the message `Cannot merge policies if either policy contains a report-to directive.`
