Breaking Change in GitHub actions/upload-artifact@v4
In GitHub's https://github.com/actions/upload-artifact/pull/598, they disabled the inclusion of dot files/hidden files by default without releasing a major version change.

As a result, the `cdk.out` uploaded by CDK Pipelines for GitHub Workflows now omit dot files. The missing dot files have begun breaking several of my pipelines that rely on `DockerImageFunction`s that reference dotfiles like `.yarnrc.yml` while building a container image asset because required files are missing from the staged assets.

We need the upload-artifact action input to include `include-hidden-files: true` so the hidden files we require are included. https://github.com/cdklabs/cdk-pipelines-github/blob/fa8d504166e3cf9d792b0a69708b395879467c54/src/pipeline.ts#L792-L796

References:
- Issue: https://github.com/actions/upload-artifact/issues/602
- Their PR: https://github.com/actions/upload-artifact/pull/598
