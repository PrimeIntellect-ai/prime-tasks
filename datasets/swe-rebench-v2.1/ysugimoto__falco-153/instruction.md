[BUG] Parser/Linter error `return;` in `vcl_recv`
**Describe the problem**
A clear and concise description of what the bug is.

False positive linter


```
sub vcl_recv {
   return;
}
```

Falco allows it but [fastly doesnt](https://fiddle.fastly.dev/fiddle/5c934b7c)

### Additional contract requirements

- A bare `return;` inside `vcl_recv` must produce a lint error, matching Fastly's rejection.
