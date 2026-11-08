`apko-publish` doesn't copy SBOM to local `sbomPath`
During the usage of [`apko-snapshot`](https://github.com/chainguard-images/actions/tree/main/apko-snapshot) action I experienced a problem at SBOM attestation step:

```console
...
Run function attest_sbom {
Unable to find SBOM on disk: sbom-index.spdx.json (arch: index). Exiting.
Error: Process completed with exit code 1.
```
I've reproduced it tweaking [`test-scan-apk.yaml`](https://github.com/andros21/actions/commit/df845b4a0bfe046d933ec6f71c5a529f75d0457e) workflow, [here its run with full logs](https://github.com/andros21/actions/actions/runs/5517957909).

It seems that since `apko` started to generate also SBOM in tempdir `apko-*`, SBOM are correctly copied in the requested `sbomPath` when using `apko-build`, thanks to this snip of code:

https://github.com/chainguard-dev/apko/blob/37b82f3a5bd85bde214df382fa974bc8dc88f692/internal/cli/build.go#L164-L170

but not when using `apko-publish`, I was wondering if this is the wanted behavior.
Thanks

### Additional contract requirements

When `apko-publish` is given `--sbom-path`, it must make the generated SBOM files available in that local directory after the command completes. If it cannot copy the requested SBOM files to that destination, the command must return an error rather than report success.
