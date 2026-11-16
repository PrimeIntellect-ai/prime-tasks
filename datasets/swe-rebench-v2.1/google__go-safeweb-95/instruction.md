Add a reports collector
Features like CSP and COOP require a report collector to be installed on the server in order to collect reports.

Implement a handler that properly parses and collects reports, sets a 204 status and passes the parsed data to a user-provided implementation of a collector handler interface.

### Additional contract requirements

Add a public package `collector` at import path `github.com/google/go-safeweb/safehttp/plugins/collector`.

Add a public function:

    collector.Handler(handler func(collector.Report), cspHandler func(collector.CSPReport)) safehttp.Handler

Add a public type `collector.Report` with exported fields `Type string`, `Age uint64`, `URL string`, `UserAgent string` and `Body interface{}`.

Add a public type `collector.CSPReport` with exported fields `BlockedURL string`, `Disposition string`, `DocumentURL string`, `EffectiveDirective string`, `OriginalPolicy string`, `Referrer string`, `Sample string`, `StatusCode uint`, `ViolatedDirective string`, `SourceFile string`, `LineNumber uint` and `ColumnNumber uint`.

The handler returned by `collector.Handler`:

- responds with status 405 Method Not Allowed to any request whose method is not POST;
- reads the request body;
- when the request `Content-Type` is `application/csp-report`, parses the body as a single CSP report and invokes `cspHandler` with the parsed `collector.CSPReport`;
- when the request `Content-Type` is `application/reports+json`, parses the body as a JSON array of reports and invokes `handler` once for each report, in order; a report whose `type` is `csp-violation` has its `body` parsed into a `collector.CSPReport`, and any other report has its `body` parsed into a `map[string]interface{}`;
- responds with status 204 No Content when every report was parsed successfully;
- responds with status 415 Unsupported Media Type when the `Content-Type` is neither of the two supported values;
- responds with status 400 Bad Request when the body is not valid JSON or a report body cannot be parsed.

A CSP report's JSON members populate the corresponding `collector.CSPReport` fields. A report received with `Content-Type: application/csp-report` may either wrap the report in a `csp-report` member or provide the report members at the top level. For a `csp-violation` report received with `Content-Type: application/reports+json`, `ViolatedDirective` is set to the report's effective directive. When both the `lineno`/`colno` members and the `line-number`/`column-number` members are present, `lineno`/`colno` take precedence.


- For `application/reports+json`, invoke `handler` for every report, including reports whose type is `csp-violation`; do not invoke `cspHandler` for these reports.
- For 405, 415, and 400 responses, set `Content-Type` to `text/plain; charset=utf-8` and `X-Content-Type-Options` to `nosniff`, and use the exact response bodies `Method Not Allowed\n`, `Unsupported Media Type\n`, and `Bad Request\n`, respectively. On a successful 204 response, send no response headers and an empty body.
