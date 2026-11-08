RFC1035 DNS Labels can be more than 63 characters long
- [x] I have looked at the documentation [here](https://pkg.go.dev/github.com/go-playground/validator/v10#section-documentation) first?
- [x] I have looked at the examples provided that may showcase my question [here](/_examples)?

### Package version eg. v9, v10:

v10

### Issue, Question or Enhancement:

The current regular expression for evaluating if a DNS label is RFC1035 compliant is:

`dnsRegexStringRFC1035Label   = "^[a-z]([-a-z0-9]*[a-z0-9]){0,62}$"`

The intention is clear (one alpha character followed by 0-62 alphanum-hypen characters followed by one alphanumeric character). However it is flawed since the max and min count accounts for everything within the parentheses. In effect this allows for unlimited length.

### Code sample, to showcase or reproduce:

The code at https://go.dev/play/p/N7bXBCE-mvl should return false but returns true.

To test it in the current main branch:

Add the following tests to TestRFC1035LabelFormatValidation in `validate_test.go`:

```
{"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk", "dns_rfc1035_label", true},
{"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl", "dns_rfc1035_label", false},
```

Run the tests. The second one will fail. It should not.

### Fix

[HIDDEN] Kubernetes and other projects does this exact same thing.

The regex should be:

[HIDDEN]

I'll submit a PR.

### Additional contract requirements

- An RFC1035 DNS label must be accepted only if it is at most 63 characters long. A valid label of exactly 63 characters is accepted; an otherwise-valid label of 64 characters is rejected.
