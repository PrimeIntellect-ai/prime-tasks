Add support to keep output directory after package/deploy
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Feature Proposal

## Description

We're trying to upload our sourcemaps to our bug tracker, Sentry. They provide a webpack plugin to do this, but it doesn't play well with multiple webpack configurations (it attempts to upload all source maps for each configuration). Instead of using the plugin, we'd like to use their cli tool. Unfortunately, serverless-webpack cleans up the output path before we have a chance to do this.

I could write a serverless plugin to slot in before serverless-webpack cleans up probably, but it'd be nice if we could just disable the cleanup step in the configuration.

Thanks!

### Additional contract requirements

- The webpack configuration accepts a boolean option `keepOutputDirectory` (default `false`) under `custom.webpack`.
- The `Configuration` class (in `lib/Configuration.js`) exposes a public `keepOutputDirectory` property that returns the configured flag, defaulting to `false`.
- When the output directory is kept, a verbose log message is emitted (when verbose output is enabled).
