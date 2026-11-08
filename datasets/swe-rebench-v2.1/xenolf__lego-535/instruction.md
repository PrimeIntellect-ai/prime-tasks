Add support for secrets in files
For applications deployed in Docker containers using Docker Swarm - secrets _must_ be stored in files instead of the environment. For reasons largely amounting to the Docker Swarm team's threat model, it seems they will never permit secrets to appear in the environment.

Many Docker images have been implementing the ability to suffix the names of environment variables with `_FILE` to cause the Docker container to read a file to get the value of a secret. For example, the WordPress Docker Image permits `WORDPRESS_DB_PASSWORD` if you wish to put the password in the environment directly, or `WORDPRESS_DB_PASSWORD_FILE` if you wish to have the Docker container read a file to determine the secret.

Lego is used by Traefik and currently my Cloudflare API keys are the only component that I can't populate from a Docker Swarm secret. Given that Traefik is often used as an ingress controller, I think that having support for a `CLOUDFLARE_API_KEY_FILE` et al for the various providers would be a significant value add.

Happy to open a pull request if there's interest in this.

### Additional contract requirements

- Add a public function `GetOrFile(envVar string) string` in package `github.com/xenolf/lego/platform/config/env`. It returns the value of the environment variable `envVar` when that variable is set and non-empty. Otherwise, when a variable named `envVar + "_FILE"` is set, it returns the contents of the file whose path is that value.
- The plain environment variable takes precedence over the `_FILE` variable when both are set.
- Cloudflare provider configuration must resolve credentials from their environment variables or, when those variables are absent, from their corresponding `_FILE` variables. For Cloudflare this includes `CLOUDFLARE_EMAIL`/`CLOUDFLARE_EMAIL_FILE` and `CLOUDFLARE_API_KEY`/`CLOUDFLARE_API_KEY_FILE`.
- File-backed environment configuration is supported across DNS providers, not only Cloudflare.
