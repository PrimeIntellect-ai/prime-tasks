failed to read apk key: open /tmp/apko-3984880358/work/local-melange.rsa.pub: no such file or directory
When building locally apko has started to fail this morning.

```
failed to read apk key: open /tmp/apko-3984880358/work/local-melange.rsa.pub: no such file or directory
```

```
--keyring-append /work/local-melange.rsa.pub --repository-append /work/packages
```

full command...
```
docker run --rm -v ${PWD}:/work -w /work cgr.dev/chainguard/apko build latest.apko.yaml foo foo.tar --debug --build-arch amd64 --keyring-append /work/local-melange.rsa.pub --repository-append /work/packages
```

I was able to go back to a previous apko version and things worked again.
```
ghcr.io/chainguard-dev/apko:cf9e6f264bcf38fd8ebbd95fb6a954cce5d16b57
```

### Additional contract requirements

- A local package repository path supplied via `--repository-append` (for example `/work/packages`) must be usable by the reported build: the repository's `APKINDEX.tar.gz` for the target architecture is read from the local filesystem. The package archive selected from that index must also be retrieved from the local filesystem during installation.
