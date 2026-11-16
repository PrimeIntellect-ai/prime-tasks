mailgun.go looks have no Interface `UpdateDomainTracking`
mailgun.go looks have no Interface `UpdateDomainTracking` .
I'm trying to import/export mailgun settings to JSON, But I have no way to update `DomainTracking` settings to domain which I created.

### Additional contract requirements

Add these methods to the `Mailgun` interface in package `github.com/mailgun/mailgun-go/v3`:

- `UpdateClickTracking(ctx context.Context, domain string, active string) error` — sends a PUT request to `/domains/{domain}/tracking/click` carrying the `active` parameter to enable or disable click tracking for the domain.
- `UpdateOpenTracking(ctx context.Context, domain string, active string) error` — sends a PUT request to `/domains/{domain}/tracking/open` carrying the `active` parameter to turn open tracking on or off for the domain.
- `UpdateUnsubscribeTracking(ctx context.Context, domain string, active string, htmlFooter string, textFooter string) error` — sends a PUT request to `/domains/{domain}/tracking/unsubscribe` carrying the `active`, `html_footer`, and `text_footer` parameters; the footers are optional.

Each method uses the supplied request-scoped context for cancellation and timeout, and returns a non-nil error when the request fails, for example when the API responds with an HTTP error status.
