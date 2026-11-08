Add Content Security Policy header to responses
Site https://webextensions.settings.services.mozilla.com has failed the web security baseline scan.

The failing tests are:

 Content Security Policy (CSP) Header Not Set [10038] x 1
 * https://webextensions.settings.services.mozilla.com/ (307 Temporary Redirect)

This issue was automatically raised.

This issue is managed automatically by the baseline scan:

 * If the failing tests change then it will be updated
 * If it is closed before the tests pass then a new one will be opened
 * When all of the tests pass then it will be closed

Full details, including how to test for these issues locally, can be found on this [Security Baseline Service](https://sql.telemetry.mozilla.org/dashboard/security-baseline-service-latest?p_w53332_site_60280=webextensions.settings.services.mozilla.com) dashboard.
If you have any questions or concerns please get in contact with @psiinon

### Additional contract requirements

- For trailing-slash redirect responses, the `Content-Security-Policy` header must contain `default-src 'none'`; for `/admin/` responses, it must contain `default-src 'self'`.
