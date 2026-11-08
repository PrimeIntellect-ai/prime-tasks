404 when downloading a GitHub release
In a project of mine I wrap a pre-built C library in a `-sys` crate (https://github.com/nbigaouette/onnxruntime-rs).

For better ergonomics I download the pre-built library in my build.rs using ureq (still on 1.4.0). This allows running tests against the library+wrapper in my CI (GitHub Actions). See: https://github.com/nbigaouette/onnxruntime-rs/blob/issue22/onnxruntime-sys/build.rs#L80-L87

The archive I want to download is `onnxruntime-linux-x64-1.4.0.tgz` from this release:
https://github.com/microsoft/onnxruntime/releases/tag/v1.4.0

The download used to work, but now it doesn't anymore. I specifically added this download so my GitHub Actions could have access to the library. Here's an example PR where the download passed: https://github.com/nbigaouette/onnxruntime-rs/pull/21

Here's an example of failure: https://github.com/nbigaouette/onnxruntime-rs/runs/1191121056?check_suite_focus=true (part of PR https://github.com/nbigaouette/onnxruntime-rs/pull/23 )

My build script prints the URL (https://github.com/nbigaouette/onnxruntime-rs/blob/issue22/onnxruntime-sys/build.rs#L210-L214) so I copy-pasted and used `curl -LO https://...` and it worked. GitHub releases uses a redirect to point to the real AWS S3 url to download. Maybe something changed in GitHub that broke how `ureq` is handling the redirects?

### Additional contract requirements

When following an HTTP redirect to a different host, the client must connect to the host named by the redirect destination, so that the redirected download can succeed.
