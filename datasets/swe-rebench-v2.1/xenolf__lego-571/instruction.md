Allow non-standard CA for validating ACME server HTTPS in development
Hi folks :wave:,

It would be wonderful if Lego was able to easily interact with a [Pebble](https://github.com/letsencrypt/pebble) instance. This is my own preferred way to debug issues with an ACME client and it may prove useful for integration testing now that Lego has the required ACME v2 support.

The only stumbling block that I'm aware of is that Lego doesn't facilitate interacting with an ACME server that has a HTTPS certificate from a CA that isn't part of the system trust store. This _can_ be worked around by adding the Pebble CA certificate to the system's CA trust store but we [specifically recommend against this](https://github.com/letsencrypt/pebble#avoiding-client-https-errors) because it can easily compromise the security of a developer's system if done carelessly or forgotten about.

Would you be interested in a feature to specify a non-standard CA certificate via command line flag or an environment variable? For instance, Certbot can be made to trust the Pebble CA by using the `REQUESTS_CA_BUNDLE` env var.

It seems like the challenge is primarily in [HIDDEN]:

https://github.com/xenolf/lego/blob/7fedfd1388f016c7ca7ed92a7f2024d06a7e20d8/acme/http.go#L18-L30

I'd be willing to submit a PR to do the work required but wanted to touch base first to see if the feature was interesting to you and whether there were recommendations on how you would like to see the `*x509.CertPool` propagated forward.

Thanks!

### Additional contract requirements

A user can configure trust for a non-standard CA used by an ACME server over HTTPS without adding that CA to the system trust store. Set `LEGO_CA_CERTIFICATES` to the path of a PEM-encoded CA certificate file; Lego must trust an ACME server certificate signed by that CA.
