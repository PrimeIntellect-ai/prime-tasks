whitelisted_domains must be set before home_url
If set `whitelisted_domains` and `home_url` at the same time using one CLI command, Facebook will throw error. Must set `whitelisted_domains` first and then with `home_url` the 2nd CLI call.
```
> bottender messenger profile set
× Failed to set messenger_profile settings
× status: 400
× data: {
  "error": {
    "message": "(#100) The web URL provided is not whitelisted for messenger extensions",
    "type": "OAuthException",
    "code": 100,
    "error_subcode": 2018063,
    "fbtrace_id": "A9EtushnqDU"
  }
}
```
