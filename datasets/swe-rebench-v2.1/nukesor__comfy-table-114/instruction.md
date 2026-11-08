[Bug] Integer overflow on large column
### Describe the bug

It was initially reported here.

https://github.com/apache/arrow-datafusion/issues/6524

Padding uses `u16`; It caused integer overflow on large table.

I wonder if it would be possible to allow users to check how big the table is going to be so that it can avoid causing overflow.

[HIDDEN]

I implemented `1.` on my fork, so if you are moving forward with `1`, I'd love to create a PR.

### Steps to reproduce

Details in the `arrow-datafusion` issue.

### Logs (if applicable)

Details in the `arrow-datafusion` issue.

### Operating system

NA

### Comfy-table version

v6.1.4

### Additional context

_No response_

### Additional contract requirements

- Rendering a table must not panic because arithmetic involving column content width and padding overflows, including when the combined width exceeds the range supported by the current width representation.
