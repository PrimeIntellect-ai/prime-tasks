Add dot notation support to `sort` filter
#1276 adds helper to support for dot-notation in `groupby` filter. [HIDDEN]

https://jinja.palletsprojects.com/en/2.11.x/templates/#sort

### Additional contract requirements

- When `throwOnUndefined` is enabled and a sort attribute resolves to `undefined`, throw an error. For `attribute="meta.age"`, the error message must include `sort: attribute "meta.age" resolved to undefined`.
