Multiple scope generation with a base image got from an openshift registry fails
Hi,

I am using [kaniko](https://github.com/GoogleContainerTools/kaniko) and ended on [an issue with openshift registries](https://github.com/GoogleContainerTools/kaniko/issues/808).

Going deeper, I spotted this was due to the fact I use a internal docker proxy

Here is my `Dockerfile`

```
FROM docker-internal-proxy/busybox:1.31.0

....
```

The `push` fails when `kaniko` does the bearer request with the scopes it deduced from the `Layer` of the image in the [Write function](https://github.com/google/go-containerregistry/blob/50b26ee28691d22901fa3f55c52bdedf6c6a0be1/pkg/v1/remote/write.go#L55)


Indeed, given the above `Dockerfile`, it tries to authenticate with the given scopes:

- `repository:test-kaniko/test-kaniko:push,pull`
- `repository:busybox:pull` (unauthorized as it should have format `<repo>/<image>`)

If I use the following `Dockerfile` (without using the internal proxy

```
FROM busybox:1.31.0

....

```

It gives the scopes

- `repository:test-kaniko/test-kaniko:push,pull`
- `repository:library/busybox:pull` (given image `busybox` url is resolved as `index.docker.io/library/busybox`)

I removed the sending of all `pull` scope (the one for the base image) and kaniko push works well

My question: why are we sending also `pull` scope? If necessary, could we add for the write operation a fallback **without** the `pull` scopes deduced from the layers of the image ? Or even uniformizing the scopes to match the required format?

Thanks

### Additional contract requirements

When uploading an image, the write operation must not request a `pull` scope for a
mountable layer whose source repository is on a different registry than the target
repository. A mountable layer whose source repository is on the same registry as the
target (but a different repository) must still contribute a `pull` scope. The push scope
for the target repository is always requested first.
