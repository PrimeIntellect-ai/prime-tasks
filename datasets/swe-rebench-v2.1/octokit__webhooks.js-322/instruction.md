support SHA-256 signature verification headers from Webhooks
follow up to https://github.com/probot/probot/issues/1379 /cc @gwestersf

> **Is your feature request related to a problem? Please describe.**
>
> GitHub will soon begin sending SHA-256 signature headers with Webhooks, when configured with a secret. The header will look like:
>
> `X-Hub-Signature-256: sha-256=kljsdfjkldasjfkaejkfwekuweur3298r2398r89fdsuf3`
>
> **Describe the solution you'd like**
>
> Probot should use the SHA-256 header instead of the SHA-1 header for verification. Note that both headers will be sent, and there is no deprecation date on SHA-1 support at this time.

I would start out by creating a test.

Here is where we currently calculate the signature using sha-1: https://github.com/octokit/webhooks.js/blob/716ee636fc73231b64659cca5bc257439d664ed3/src/sign/index.ts#L11

The signatures have `sha1=` / `sha256=` prefixes respectively, they also have different lenghts. We shouldn't need to introduce any new APIs to differentiate the two. We should be able to implement both with full backwards compatibility
