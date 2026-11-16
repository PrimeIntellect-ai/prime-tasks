Implement updating a Floating IP
https://docs.hetzner.cloud/#resources-floating-ips-put

### Additional contract requirements

Expose this operation as `FloatingIPClient.Update(ctx context.Context, floatingIP *FloatingIP, opts FloatingIPUpdateOpts) (*FloatingIP, *Response, error)`. It updates the specified Floating IP via the documented PUT operation; the options may include a `Description` string to update. On success, return the Floating IP provided by the API and response metadata. If request creation or the API call fails, return a non-nil error.
