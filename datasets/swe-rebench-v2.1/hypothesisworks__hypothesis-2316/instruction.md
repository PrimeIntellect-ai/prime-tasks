Add a strategy for `ipaddress` address objects, deprecate provisional strategy for IP addr strings
Now that Hypothesis is Python-3-only (:tada:), there are some useful things we can rely on having available - like [the `ipaddress` module](https://docs.python.org/3/library/ipaddress.html)!  I think that we should:

- Add a strategy `ip_addresses(*, v=None, network=None)`.  `v` may be either `4` or `6`; `network` may be an `IPv4Network` or `IPv6Network` object (or string - I think the ergonomics justify handling the cast internally).
- Deprecate `hypothesis.provisional.ip{4,6}_addr_strings()` in favor of `ip_addresses(v=...).map(str)`
- Register strategies for `IPv{4,6}{Address,Network,Interface}` by entering them in the `_global_type_lookup` mapping in `hypothesis.strategies._internal.types`

### Additional contract requirements

- When neither `v` nor `network` is supplied, `ip_addresses()` can generate both IPv4 and IPv6 address objects.
