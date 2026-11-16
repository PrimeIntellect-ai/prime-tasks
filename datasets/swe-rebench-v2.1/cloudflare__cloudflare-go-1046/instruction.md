Double-unmarshalling of `config` from cfd_tunnel/{{TUNNEL_ID}}/configurations is unnecessary
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

0.46.0

### Go environment

Not relevant.

### Expected output

I was expecting to use `GetTunnelConfiguration` and `UpdateTunnelConfiguration`.
However, it seems like those methods are no longer compatible with the latest version of the API at https://api.cloudflare.com/#cloudflare-tunnel-configuration-properties

I traced the error down to the double-marshaling that was done in https://github.com/cloudflare/cloudflare-go/pull/948#issuecomment-1166701661.

### Actual output

Error unmarshalling.

`2022/08/16 12:38:25 Failed to get config for current tunnel: error unmarshalling the JSON response: json: cannot unmarshal object into Go struct field TunnelConfigurationStringifiedConfigResult.result.config of type string`

### Code demonstrating the issue

	// Get the current configuration
	currentConfig, err := api.GetTunnelConfiguration(ctx, cloudflare.AccountIdentifier(accountId), tunnelId)
	if err != nil {
		if _, ok := err.(*cloudflare.NotFoundError); ok {
			shouldCreateFromScratch = true
		} else {
			log.Fatal("Failed to get config for current tunnel: ", err)
		}
	}

### Steps to reproduce

1. Create a sample go project that uses v0.46.0 of the API.
2. Ensure that you have Cloudflare Tunnel with a Cloudflare Tunnel Configuration.
3. Attempt to get/update the tunnel configuration
4. Notice the serialization error

### References

https://github.com/cloudflare/cloudflare-go/pull/948#issuecomment-1166701661
