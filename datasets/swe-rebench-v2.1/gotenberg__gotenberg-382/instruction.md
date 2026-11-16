Support Proxy Server for Chromium Headless
Hi

Is there any way to support a proxy server for the chromium module? I have tried setting the system proxy, but that doesn't seem to do the trick. So there's still the `--proxy-server` flag for `chromium` but I guess that's not supported, is it?

### Additional contract requirements

The Chromium module must expose a `--chromium-proxy-server` command-line flag that
configures the outbound proxy server used by Chromium. The flag default value is the
empty string, which means that no proxy server is configured.
