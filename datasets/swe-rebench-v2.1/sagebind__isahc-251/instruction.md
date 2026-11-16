Breaking change from 0.9.10 to 0.9.11 due to #240 (presumably)
#240 rewrote the redirect implementation away from curl. I noticed that this broke redirects in my use case.

Test code:

```rust
use isahc::{
    config::{Configurable, RedirectPolicy},
    http::request::Request,
    HttpClient,
};
use std::error::Error;

#[async_std::main]
async fn main() -> Result<(), Box<dyn Error + Send + Sync>> {
    let client = HttpClient::builder()
        .redirect_policy(RedirectPolicy::Limit(8))
        .build()
        .expect("FATAL: failed to create http client");

    let req = Request::post("http://localhost:8265/command/help").body(())?;
    let res = client.send_async(req).await?;
    dbg!(res);
    Ok(())
}
```

The URL issues a 302 redirect.

### Output with isahc 0.9.10

```
[src/bin/isahc-test.rs:21] res = Response {
    status: 200,
    version: HTTP/1.1,
    headers: {
        "server": "nginx/1.18.0",
        "date": "Tue, 10 Nov 2020 08:09:31 GMT",
        "content-type": "text/plain",
        "content-length": "614",
        "last-modified": "Thu, 05 Nov 2020 10:51:25 GMT",
        "connection": "keep-alive",
        "etag": "\"5fa3d92d-266\"",
        "accept-ranges": "bytes",
    },
    body: Body(614),
}
```

### Output with isahc 0.9.11

```
[src/bin/isahc-test.rs:21] res = Response {
    status: 302,
    version: HTTP/1.1,
    headers: {
        "server": "nginx/1.18.0",
        "date": "Tue, 10 Nov 2020 08:04:33 GMT",
        "content-type": "text/html",
        "content-length": "145",
        "location": "http://localhost:8265/static/help.txt",
        "connection": "keep-alive",
    },
    body: Body(145),
}
```
