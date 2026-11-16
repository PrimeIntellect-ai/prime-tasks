cmd/main: PREVENT_INSECURE_STARTUP option
<!-- Please fill out the following questions, thanks! -->

Customers Version: `v0.5.0-dev`

**What were you trying to do?**
The Customers service is starting to have several security-sensitive configuration knobs. With the default being insecure values this means one of them could be missed and operators are unaware they've missed a configuration.

**What did you expect to see?**
A configuration option that will panic/crash if insecure (e.g. default) configuration is used.

### Additional contract requirements

- The configuration option is the environment variable `PREVENT_INSECURE_STARTUP`, parsed as a boolean. When it is unset or not a valid boolean it defaults to `false`.
- When `PREVENT_INSECURE_STARTUP` is enabled and any required security option is missing, the service must refuse to start: it logs a message containing `prevented insecure startup` and terminates instead of continuing to serve requests.
- When `PREVENT_INSECURE_STARTUP` is disabled or unset, the service logs a warning about the insecure configuration and continues to start.
- The security options checked at startup are `APP_SALT` and `TRANSIT_LOCAL_BASE64_KEY` in all configurations; `SSN_SECRET_KEY` when `SSN_SECRET_PROVIDER` is unset or `local`; `DOCUMENTS_SECRET_KEY` when `DOCUMENTS_SECRET_PROVIDER` is unset or `local`; and `FILEBLOB_HMAC_SECRET` when `DOCUMENTS_STORAGE_PROVIDER` is unset or `file`. A local-only option is not required when its corresponding provider is configured to a nonlocal provider.
