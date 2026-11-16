GuzzleTracingMiddleware can potentially leak private data in baggage header
### How do you use Sentry?

Self-hosted/on-premise

### Version

3cefa7b69f2ebb4e0042c4f39e5c18bf573a4cab

### Steps to Reproduce

I noticed that the GuzzleTracingMiddleware adds the baggage header, which contains various metadata such as the transaction name, to all outbound requests to external URLs.

I'm concerned that some data that isn't intended to be shared with third-parties could be sent via this avenue. For example, the transaction name might include the URL that is currently being accessed, which might include some secret or identifying tokens in the path or query string.

Whereas previously, only a relatively harmless sentry-trace identifier was being sent.

It seems like, by default, sending extra baggage data needs to be limited to certain acceptable external hosts?  Or at a minimum, usage of this middleware needs to be much better documented?

### Expected Result

No data is sent unintentionally to remote sites.

### Actual Result

A baggage HTTP header is sent to remote site, which might contain something like `sentry-trace_id=0123456789,sentry-sample_rate=1,sentry-transaction=GET%20http%3A%2F%2Fdev.example.com%2Fpassword%2Freset%3Ftoken%3Dsecret,sentry-public_key=0123456789,sentry-release=beta,sentry-environment=dev`

### Additional contract requirements

The Guzzle tracing middleware must send baggage only when the outbound destination has been deemed acceptable for trace propagation. With no acceptable destinations configured, it must not send baggage to any destination. This restriction applies to baggage; it does not require suppressing the sentry-trace header or other existing tracing behavior. Configure acceptable destinations with the `trace_propagation_targets` option, which accepts a list of hostnames.
