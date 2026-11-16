Add the field `Digest` to ReleaseAsset
https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28#get-a-release

The `Get a Release` API returns digests of assets.

To get digests, we need to add the field `Digest` and the method `GetDigest` to `ReleaseAsset`.

https://github.com/google/go-github/blob/8759b171221b1b3378cdeb3f83dea5ec344efd53/github/repos_releases.go#L67-L82

I'll send a pull request soon.
