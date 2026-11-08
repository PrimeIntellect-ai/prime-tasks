Return error `400`  for unsupported propfind depths
I understand this is a minimal implementation, not fully implementing all spec, but here's a tiny reasonable request:

Return error `400`  for unsupported propfind depths (I guess anything other than `0` and `1`) like nginx does. The depth is in the header and should be readily available.

Related to https://github.com/sigoden/dufs/issues/387

### Additional contract requirements

- For an unsupported depth, the response body must be exactly `Invalid depth: only 0 and 1 are allowed.`
