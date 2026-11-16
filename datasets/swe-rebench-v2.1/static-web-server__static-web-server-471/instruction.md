Incorrect `content-encoding` for `gzip` when file is already available + `compression-static`
### Search for duplicate issues

- [X] I already searched, and this issue is not a duplicate.

### Issue scope

Docker / Kubernetes

### Describe the bug

If I run `SWS` with my "frontend" package, with both regular and pre-compressed files (`.gzip`), I see an unexpected `content-encoding` returned by `SWS`: `content-encoding: gzip, gzip`.

After verification, the content is packaged twice, aka a `gzip` inside a `gzip`.

This generates issues with Apple based browsers, because they don't process `gzip` twice and so can't parse `js` or `css` after the first "unpackaging".



### How to reproduce it

Find attached files I have generated, with the unexpected result in `SWS`:

[app-css.zip](https://github.com/user-attachments/files/16589058/app-css.zip)

If I run the `SWS` with `docker run -it --rm -p 8080:8080 ui-for-testing`, using the following configuration:

```toml
[general]

host = "::"
port = 8080
log-level = "info"

cache-control-headers = true
compression = true
compression-static = true
security-headers = true
directory-listing = false
redirect-trailing-slash = true
ignore-hidden-files = true
```

I get the following result when I run the following `curl` call:

```sh
curl 'http://localhost:8080/app.min.css' \
      -H 'Accept: */*' \
      -H 'Accept-Encoding: gzip' \
      -v -o nul &| grep content-encoding
< content-encoding: gzip, gzip
```

If I set `compression-static = false`, the result is "normal", but I suspect the compression is done by `SWS` and doesn't leverage the pre-built `gzip` file.

```
curl 'http://localhost:8080/app.min.css' \
      -H 'Accept: */*' \
      -H 'Accept-Encoding: gzip' \
      -v -o nul &| grep content-encoding
< content-encoding: gzip
```

### Expected behavior

I expect the system to leverage the pre-build `gzip` and returns a `content-type` with only `gzip` once.



### Complementary information

From the investigation I did, this bug has been introduced after `2.31.0`.

If I change my `Dockerfile` to `2.32.0`, I have the issue, but I don't have it with `2.31.0`, of course with the same config and files.



### Build target

Docker linux/amd64

### Environment and specs

- [x] **static-web-server:** [e.g. v2.32.0+]
- [ ] **Rust:** [e.g. v1.78.0]
- [x] **OS:** Distrolesss
- [x] **Arch:** x86_64 (64-bit), ARM (32-bit), ARM64 (64-bit)
- [x] **Docker:** 27.1.1
- [x] **Client:** All (Safari, Chrome, Arc, `curl`)


### Additional context

This issue has been found while developing on my application, [Podcast-Server](https://gitlab.com/davinkevin/Podcast-Server/), and you can find the code used by the UI [here](https://gitlab.com/davinkevin/Podcast-Server/-/tree/main/ui/src/docker?ref_type=heads)
