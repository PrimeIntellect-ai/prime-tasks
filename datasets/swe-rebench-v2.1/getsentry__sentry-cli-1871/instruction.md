`sourcemaps inject` should fall back to co-located source maps if exact path can't be found
### Environment

What version of the CLI and what OS are you running?

Sentry CLI 1.23.0, macOS Ventura 13.4

### Steps to Reproduce

Similar to #1846:
1. Create a `.js` file with a corresponding `.js.map` file in the same directory
2. Add a source map comment pointing to a path that doesn't exist locally; e.g.
   ```
   //# sourceMappingURL=/_static/build/foo.js.map
   ```
   Note: this is a mostly-real example from a starter Remix app. The path here is the default when creating a new app from the [grunge stack](https://github.com/remix-run/grunge-stack), but this issue will occur for any static assets path, whether or not it has a URL scheme and domain.
3. Run `sentry-cli sourcemaps inject foo.js*`

Alternatively, though it was created to repro a different bug, you can also repro this bug by following the steps [here](https://github.com/brettdh/sentry-remix-lambda-esm-variables), ignoring the AWS bits and running `npm run build` instead of any of the other scripts. The `sentry-cli sourcemaps inject` step will show missing debug IDs for the sourcemap files.

### Expected Result

JS file and sourcemap file both have debug ID injected

### Actual Result

Only JS file has debug ID injected

### Logs

When filing a bug report, please attach debug logs, either by using `--log-level=debug` flag or `SENTRY_LOG_LEVEL=debug` environment variable.
