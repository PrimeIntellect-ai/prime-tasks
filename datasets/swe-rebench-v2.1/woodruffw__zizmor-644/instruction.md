[BUG]: setup-buildx-action false positive for cache poisoning audit
Hi, maintainer of Docker GitHub Actions here.

The following check is not quite right:

https://github.com/woodruffw/zizmor/blob/ccd4178eb5276bd0bd17f2e814a921959ff67517/src/audit/cache_poisoning.rs#L109-L114

Even if `cache-binary` is `true`, it will not write or read from cache if `version` is not set. By default it will use buildx binary available on GitHub runner: https://github.com/actions/runner-images/blame/main/images/ubuntu/Ubuntu2404-Readme.md#L74

I think this should check for both `version` input being set and `cache-binary` set to `true`.
