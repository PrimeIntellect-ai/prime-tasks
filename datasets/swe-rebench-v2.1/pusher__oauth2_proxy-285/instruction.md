Feature request: Redirect to HTTPS
## Current Behavior

We are running this excellent of oauth2_proxy on Heroku using this build-pack: https://github.com/cfra/heroku-buildpack-oauth2-proxy

oauth2_proxy runs as reverse proxy in front of an nginx which serves static files.

When I access the heroku application using plain HTTP, the "login with github" button will be shown and the cookie will be set, all without encryption.

After authenticating with GitHub, we get redirected to the oauth2 callback, but this time via HTTPS, because such is the configuration in GitHub. (And oauth2 spec recommends to only use HTTPS anyway)

This will lead to oauth2_proxy showing an error that a required cookie is missing, because the cookie set via HTTP is not taken into the HTTPS session.

After clicking "login" again and doing everything over HTTPS, it works fine.

## Possible Solution

As the operation of oauth2_proxy as a user-facing reverse proxy seems to be a possible mode of deployment, it would be useful if there was an option to redirect all traffic to HTTPS.

### Additional contract requirements

- The option is exposed as the boolean command-line flag `-force-https` (default `false`).
- When the option is enabled, the running proxy must redirect incoming non-HTTPS requests to the configured HTTPS address with `http.StatusPermanentRedirect`; enabling the option must change how the proxy handles incoming traffic.
