New configuration option to ignore anchor links?
### Is your feature request related to a problem?

Hey hey, love all the stuff you've built (we're just getting used to it on [developers.cloudflare.com](https://developers.cloudflare.com)).

As part of our previous build workflow (in Hugo), we had the following split between evaluating internal links:

- Every commit -> Broken internal links (and check for build + infinite redirects). This check was required.
- Every weekend -> Maintenance check for broken anchor links.

Essentially, it just wasn't worth it to fail the build for anchor links b/c we have a metric ton of content + we didn't want to inconvenience contributors.

### Describe the solution you'd like

Would it be possible to add a new [configuration option](https://starlight-links-validator.vercel.app/configuration/) where the link checker ignores the anchor part of links?

I'd love to be able to tap into the logic you've already built... but be able to tailor it a bit more specifically.

### Describe alternatives you've considered

I've thought about writing something from scratch, but it seems like this is very close to our use case.

### Additional Context

_No response_

### Additional contract requirements

The configuration option is named `errorOnInvalidHashes`. It defaults to `true`, preserving validation of missing fragments when omitted. Set it to `false` to ignore invalid hash fragments in internal links while continuing to validate whether each target page exists.
