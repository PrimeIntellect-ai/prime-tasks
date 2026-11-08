[BUG] Request context cancellation is ignored when `retryBackoff` is configured
When `retryBackoff` is configured, the client sleeps between retries and ignores request context cancellation.

In short, the same issue as the one in the origin [ES client](https://github.com/elastic/go-elasticsearch/issues/300). The fix has not yet been ported to the [OpenSearch client](https://github.com/opensearch-project/opensearch-go/blob/216cc6fdba9c94b819b45afb3ed7eed67306384d/opensearchtransport/opensearchtransport.go#L381-L384)

### Additional contract requirements

Configured retry backoff must respect cancellation of the request context. If cancellation occurs while a retry is waiting, the wait ends promptly, `Perform` returns the context error, and no further attempt is made.
