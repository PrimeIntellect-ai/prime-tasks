[MacOS] Add flag to specify custom system CA Path
Today setup `proxy.py` on a fresh Macbook (Catalina) and observed Apple has further made it harder to reliably run interceptor.  Had to hardcode `certifi` ca file to make it work

<img width="920" alt="Screen Shot 2020-03-24 at 9 59 39 PM" src="https://user-images.githubusercontent.com/126065/77451514-c7e37880-6e1a-11ea-971a-50094980c5a8.png">

Also see https://stackoverflow.com/questions/57630314/ssl-certificate-verify-failed-error-with-python3-on-macos-10-15 for some background.

### Additional contract requirements

The custom system CA path is exposed as the command-line flag `--ca-file`
and stored on `Flags` as the attribute `ca_file` (default `None`). When a
custom CA file is supplied, it is used as a trust source for validating
upstream TLS peer certificates, and peer-certificate verification remains
enabled.
