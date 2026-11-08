Panic on invalid path
Hello,
I'm building a service and I'm using warp to for the http stack and at some point I had a malformed request and warp just panicked instead of returning an error for me to handle somehow...

The malformed request was
```
GET foo.txt HTTP/1.1


```
as you can see there's a missing slash at the start of the path, if I add it everything works fine...

This is the warp server code:
```
let warp = warp::get().and(warp::fs::dir(path)).with(warp::log::log("static webserver");
warp::serve(webserver).run(ADDR).await;
```

Backtrace [here](http://ix.io/2ll6).
This is the line just before the panic:
```
15: warp::filters::path::path_and_query
             at /home/karrq/.cargo/registry/src/github.com-1ecc6299db9ec823/warp-0.2.2/src/filters/path.rs:465
```
