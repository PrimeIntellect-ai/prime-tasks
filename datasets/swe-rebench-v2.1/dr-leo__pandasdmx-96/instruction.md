Convert Request.url() to a top-level convenience method
As raised by @dr-leo via e-mail:

> On Request.url: I'd prefer a confenience function rather than a classmethod. It is wierd that a single class provides two ways to do the same thing (alongside with url kwarg of .get()). A convenience function 'get_url' or something [HIDDEN] Thus, the cache may be used even from the convenience function. But this is a minor quirk. I'd be fine with removing the classmethod in the first place so users must instantiate themselves.

### Additional contract requirements

- Expose a top-level convenience function through the package API so callers can request a URL without constructing a `Request`; the function returns the result of the URL request. No particular function name is required.
- Callers can pass supported request options through this function, including `use_cache`, and they have the same observable effect as when supplied to the request operation.
- Replace the `Request.url()` classmethod with the top-level convenience function; do not retain `Request.url()` alongside it.
