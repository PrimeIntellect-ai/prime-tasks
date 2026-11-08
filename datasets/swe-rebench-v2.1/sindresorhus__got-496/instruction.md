Opting out of default user-agent
Hi,

The `user-agent` header is optional in RFC 2616, it shouldn't be enforced imo. Currently there is no way to send a request without the `user-agent` header.

Happy to submit a PR to make this happen.

### Additional contract requirements

- Setting the `user-agent` request header to `null` in the request options must send the request without any `user-agent` header.
- All other requests keep sending the default `user-agent` header.
