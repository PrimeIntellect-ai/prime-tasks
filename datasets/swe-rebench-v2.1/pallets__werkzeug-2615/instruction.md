If the "Accept" header contains a media-type with a quoted parameter including a space, the resulting MIMEAccept instance is incorrect
According to [RFC 2045 Section 5.1](https://tools.ietf.org/html/rfc2045#section-5.1), mime-type parameters can be quoted. As additional reference, the `quoted-string` is defined in [RFC 7230 Section 3.2.6](https://tools.ietf.org/html/rfc7230#section-3.2.6) (which is the same as in [RFC 2616 Section 2.2](https://tools.ietf.org/html/rfc2616#section-2.2))

This means that the following media-type is a valid media-type string:

    fictitious/media-type; myparam="some value"

Currently, `werkzeug` sees this as `fictitious/media-type; myparam="some`, which includes the first double-quote, but drops the rest. Additionally, the parsed `MIMEAccept` instance also contains an entry for `('value"', 1)`. In other words, the above media-type results in the following two entries in the `MIMEAccept` instance:

* `('fictitious/media-type; myparam="some', 1)`
* `('value"', 1)`

Appending `q=0.5` results in this:

* `('fictitious/media-type; myparam="some', 1)`
* `('value"', 0.5)`

I would expect it to contain just one entry as `('fictitious/media-type; myparam="some value"', 1)`

We currently get one such media-type in an accept header and cannot use the normal werkzeug "accept" mechanism which makes this cumbersome. I just discovered this so I still need to write a workaround. I am considering appending the solution as a PR to this ticket. I already have a compliant parser lying around, which is based on a *very* simple state-based parser.
