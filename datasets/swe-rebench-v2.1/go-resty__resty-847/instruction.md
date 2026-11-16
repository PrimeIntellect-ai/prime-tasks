Add clone method in `Request`
### Discussed in https://github.com/go-resty/resty/discussions/588

<div type='discussions-op-text'>

<sup>Originally posted by **shotamakino** October 11, 2022</sup>
Hi, thank you for this great package!

I am trying to clone a `Request` instance in order to reuse it again with a different set of query parameters (for pagination). I was wondering if there's some kind of support for a `Clone` method similar to https://pkg.go.dev/net/http#Request.Clone?
</div>

### Additional contract requirements

A cloned request retains the source request's configured state so it can serve as a reusable base request. Changing query parameters on the clone must not change the original request's query parameters.
