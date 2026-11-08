X-Frame-Options header is deprecated
### Environment

* Elixir version (elixir -v):
	Erlang/OTP 27 [erts-15.1.2] [source] [64-bit] [smp:10:10] [ds:10:10:10] [async-threads:1] [jit]
	Elixir 1.17.3 (compiled with Erlang/OTP 27)

* Phoenix version (mix deps): phoenix 1.7.14
* Operating system: MacOS 15.1 ARM
* Firefox 132.0.2

### Actual behavior

From MDN: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options
X-Frame-Options

Deprecated: This feature is no longer recommended. Though some browsers might still support it, it may have already been removed from the relevant web standards, may be in the process of being dropped, or may only be kept for compatibility purposes. Avoid using it, and update existing code if possible; see the [compatibility table](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options#browser_compatibility) at the bottom of this page to guide your decision. Be aware that this feature may cease to work at any time.

Warning: Instead of this header, use the [frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/frame-ancestors) directive in a [Content-Security-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy) header.

### Additional contract requirements

`Phoenix.Controller.put_secure_browser_headers/2` must set the following response
headers when they are not already present:

  * `content-security-policy` set to `"base-uri 'self'; frame-ancestors 'self';"`
  * `x-content-type-options` set to `"nosniff"`
  * `x-permitted-cross-domain-policies` set to `"none"`

It must not set the deprecated `x-frame-options` header. A custom headers map may be
passed to override the defaults, and existing response headers must be preserved.
