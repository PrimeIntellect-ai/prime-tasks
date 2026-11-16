Add end-user function to generate CSP report-uri
### Problem Statement

It is possible to use Sentry as endpoint for collecting CSP violations, see https://docs.sentry.io/product/security-policy-reporting/. In order to do so, it requires passing a specific report-uri value to the CSP header in the response of your application. It would be great if the SDK would be able to generate such an URI.

### Solution Brainstorm

The [Raven: Sentry Integration](https://www.drupal.org/project/raven) module for Drupal has an implentation of this, see https://git.drupalcode.org/project/raven/-/blob/4.x/src/Plugin/CspReportingHandler/Raven.php. It would be great to have a public function for this URI in any application using Sentry PHP SDK.

### Additional contract requirements

- Add a public method `getCspReportUrl(): ?string` on the client (`Sentry\Client`). It returns the full CSP report URL generated from the configured DSN, optionally appended with `sentry_release` and `sentry_environment` query parameters taken from the configured release and environment options. It returns `null` when no DSN is configured.
- Add a public method `getCspReportEndpointUrl(): string` on `Sentry\Dsn`. It returns the CSP report endpoint formatted as `<base>/security/?sentry_key=<publicKey>`, where `<base>` is the DSN base URL and `<publicKey>` is the DSN public key.
- When both the release and environment options are set, the query parameters are ordered `sentry_release` followed by `sentry_environment`.
