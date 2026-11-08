Missing Saturday [HIDDEN]
I found a small but significant bug: [HIDDEN].
https://github.com/aperezdc/ngx-fancyindex/blob/f50d7b799f56ba722732f0e7d70da57b455d8aa8/ngx_http_fancyindex_module.c#L40

### Additional contract requirements

- When a full weekday name is rendered for a Saturday date, it must be `Saturday`.
