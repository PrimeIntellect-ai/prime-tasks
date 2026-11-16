Second parameter to `fancyindex_header`/`fancyindex_footer` is not always optional
I just gave version 0.5.0 a spin but my configuration breaks with following error message:
```
# nginx -t
nginx: [emerg] unknown header/footer kind "/tools/memdisk" in /etc/nginx/nginx.conf:107
nginx: configuration file /etc/nginx/nginx.conf test failed
```
if the order of directives is like that
```
fancyindex_footer               "/fancyindex/footer.html";
fancyindex_header               "/fancyindex/header.html" subrequest;
```
If I swap those lines, the configuration validates and loads (init issue?).

And the even more curious thing is that `/tools/memdisk` mentioned in the error message isn't even part of the `server` stanza where fancyindex is being used. But it is rather the **last** location of the `server` stanza defined **before** the `server` in question. I have no idea how Nginx works internally but this seems off-by-one if all locations are indexed sequentially.

This is Nginx 1.18.0 (self-compiled) on a CentOS 8 box. For now I will always specify the second parameter.

### Additional contract requirements

- The `fancyindex_header` and `fancyindex_footer` directives accept an optional second parameter that names the kind of path. When this parameter is omitted, the kind defaults to `subrequest`.
- The accepted kind values are `subrequest` and `local`.
- When the kind parameter is present but is not one of the accepted values, nginx must reject the configuration (fail to load it) and log an error.
- A path-only footer followed by a header explicitly using `subrequest` must be accepted even when an unrelated server and location appear earlier in the configuration.
