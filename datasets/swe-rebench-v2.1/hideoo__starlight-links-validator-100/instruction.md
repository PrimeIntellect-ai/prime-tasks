Ability to evaluate "external" links that are really just internal links
### Is your feature request related to a problem?

Limitation when people specify a link externally (`https://developers.cloudflare.com/workers/`) that should really be evaluated (and flagged) as if they're internal links (`/workers/`).

This situation skips evaluation, as demonstrated in this [test PR](https://github.com/cloudflare/cloudflare-docs/pull/19799/files#diff-0e116de756c88231bc3c18adc9465a833e6d9210b0039c12fcaeabd01adc2238R20) || [CI run](https://github.com/cloudflare/cloudflare-docs/actions/runs/13183588128/job/36800222268?pr=19799#step:9:11367)



### Describe the solution you'd like

I'd love it if you were able to specify a `host` or at least a pattern to ignore so that these links would be evaluated as internal.

That way, we could accept the links and know that they were valid and then fix in the background gradually.

### Describe alternatives you've considered

We have linting around this in PRs, but it does add friction for contributors.
https://github.com/cloudflare/cloudflare-docs/pull/19799/files#r1945066002

As long we can evaluate these links successfully, we'd love to just not even worry about this in reviews and fix these on a cadence.

### Additional Context

_No response_

### Additional contract requirements

The plugin accepts an options object with the following fields:

- `sameSitePolicy`: one of `'error'`, `'ignore'`, or `'validate'`, defaulting to `'ignore'`. It controls how external links whose origin matches the Astro `site` option are handled: `'ignore'` leaves them unvalidated, `'error'` reports them as errors, and `'validate'` validates them as internal links.

Same-site external links reported under the `'error'` policy use the error type `SameSite`, whose value is `{{site}} can be omitted`, with `{{site}}` replaced by the configured site origin. This error type is a member of the `ValidationErrorType` object exported from `packages/starlight-links-validator/libs/validation.ts`.

The public type `StarlightLinksValidatorOptions` exported from `packages/starlight-links-validator/index.ts` includes the `sameSitePolicy` field.

The public type `RemarkStarlightLinksValidatorConfig` exported from `packages/starlight-links-validator/libs/remark.ts` includes the fields `base: string`, `options`, `site`, and `srcDir: URL`.

The public type `Link` exported from `packages/starlight-links-validator/libs/remark.ts` includes the fields `raw: string`, `transformed`, and `error`.


- In the build output, this error message must be displayed as `{{site}} can be omitted`, with `{{site}}` replaced by the configured site origin.
