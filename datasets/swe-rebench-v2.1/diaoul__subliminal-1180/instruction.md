Pass arguments to providers through the CLI
Right now we can pass arguments to the providers only through the config file.
Because of the extension system, we cannot set the arguments of each and every providers as hard-coded options for the CLI. However, `click` allows to add dynamic options!

The scheme for the provider (and refiner) arguments I thought about is:
`--provider.opensubtitles.username=user`

The variable names are `_provider__opensubtitles__username`, note the double underscores to be able to split the variables if an underscore is present in an argument name or provider name, for instance `_provider__addic7ed__allow_searches`.

We could also add support for passing options to the CLI with environment variables (easy to do with `click`).
The scheme would be:
`SUBLIMINAL_PROVIDER_OPENSUBTITLES_USERNAME` (with single underscores).

### Additional contract requirements

- Provider and refiner arguments supplied on the command line are forwarded as keyword arguments to the corresponding provider or refiner constructor. For example, `--provider.opensubtitles.username=user` causes the opensubtitles provider to be constructed with `username='user'`.
- The opensubtitles provider raises a `ConfigurationError` when a username is supplied without a password.
- Refiner arguments use the same scheme with the `refiner` prefix, for example `--refiner.omdb.apikey=key`.
