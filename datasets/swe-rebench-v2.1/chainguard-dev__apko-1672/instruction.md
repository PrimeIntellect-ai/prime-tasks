Inconsistent merging of upstream source packages from package SBOM into image SBOM
In https://github.com/chainguard-dev/melange/pull/1474, we updated melange to include SPDX packages in APK SBOMs to represent upstream sources (such as what's found in `git-checkout` and `fetch` pipeline steps).

And in https://github.com/chainguard-dev/apko/pull/1366, we fixed up some of the apko SBOM logic to account for melange's SBOM enhancements in the image SBOMs.

However, now we're seeing instances of **upstream source packages missing from the image SBOM**. For example, the Chainguard Image `cgr.dev/chainguard/jdk ` uses the Wolfi package `ca-certificates-bundle`, which exposes its upstream source in its package SBOM (see SPDX package with ID `SPDXRef-Package-gitlab.alpinelinux.org-alpine-ca-certificates...`). But that SPDX package is **not found** in the jdk image's SBOM.

```sh
cosign download attestation \
  --platform linux/amd64 \
  --predicate-type=https://spdx.dev/Document \
  cgr.dev/chainguard/jdk:latest | \
  jq '.payload | @base64d | fromjson | .predicate' | \
  grep 'SPDXRef-Package-gitlab.alpinelinux.org-alpine-ca-certificates'
```

Even stranger, it looks like **sometimes this problem doesn't happen**. The image `cgr.dev/chainguard/go` similarly uses `ca-certificates-bundle`, and its image SBOM **does have** the upstream source package intact.

```sh
cosign download attestation \
  --platform linux/amd64 \
  --predicate-type=https://spdx.dev/Document \
  cgr.dev/chainguard/go:latest | \
  jq '.payload | @base64d | fromjson | .predicate' | \
  grep 'SPDXRef-Package-gitlab.alpinelinux.org-alpine-ca-certificates'
```

We need to ensure that apko is consistently including all relevant information from the SBOMs of the packages that comprise the image into the image's SBOM.

cc: @dustinkirkland
