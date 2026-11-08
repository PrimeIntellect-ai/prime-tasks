Allow CF_API_KEY and CF_API_EMAIL as alternative environment variables for Cloudflare
From https://github.com/caddyserver/dnsproviders/issues/22

The cloudflare tools use those environment variable names. If lego can switch, or read from both, then that makes compatibility with those tools easier. :)

https://github.com/cloudflare/python-cloudflare
https://github.com/cloudflare/cloudflare-go/tree/master/cmd/flarectl
