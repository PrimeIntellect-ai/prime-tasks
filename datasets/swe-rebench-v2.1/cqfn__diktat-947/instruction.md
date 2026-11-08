package naming: Allow default package in kotlin files in buildSrc
For example, because of old and well-known bug in gradle, a common pattern to use `object Versions {...}` to describe all versions requires `Versions` to be from default package.
