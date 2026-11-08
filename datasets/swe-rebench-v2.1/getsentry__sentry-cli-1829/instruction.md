Uploadling source maps fails silently, if none are found
### Environment

Hi there, we are using sentry-cli to upload source map files from a github runner.
We changed our output dir of our project recently and didn't correct that path in the sentry-cli upload command.
Unfortunately the cli does not report this as an error, so we discovered some missing source maps later own wondering why some are there and some are not.

### Steps to Reproduce

Pass a wrong path to sentry-cli to upload source map files.
E.g.:

`sentry-cli releases files $BUILD_VERSION upload-sourcemaps /tmp/foo'`

### Expected/Actual Result

sentry-cli should throw an error / break the build in case the upload command does not do anything.
At least a strict mode (as per toggle, e.g. --strict) would be appreciated.

### Logs

Failed attempt log output

```
2023-07-31T09:45:14.1015340Z $ sentry-cli releases files $BUILD_VERSION upload-sourcemaps build/webpack/static/foo/dist --rewrite --url-prefix '~/foo/dist'
2023-07-31T09:45:14.1015956Z > Rewriting sources
2023-07-31T09:45:14.1016458Z > Adding source map references
2023-07-31T09:45:14.1017127Z > Nothing to upload
2023-07-31T09:45:14.1017384Z Done in 0.35s.
```

vs fixed path (note the ../):

```
2023-07-31T09:53:11.5534360Z $ sentry-cli releases files $BUILD_VERSION upload-sourcemaps ../build/webpack/static/foo/dist --rewrite --url-prefix '~/foo/dist'
2023-07-31T09:53:11.5534936Z > Found 17 files
2023-07-31T09:53:11.5535231Z > Analyzing 17 sources
2023-07-31T09:53:11.5535543Z > Rewriting sources
2023-07-31T09:53:11.5535898Z > Adding source map references
2023-07-31T09:53:11.5536242Z > Bundled 17 files for upload
2023-07-31T09:53:11.5536683Z > Bundle ID: 68c59ed6-1603-59a0-b3d4-e2f6384d8cf8
2023-07-31T09:53:11.6532171Z > Uploaded files to Sentry
2023-07-31T09:53:11.7532153Z > File upload complete (processing pending on server)
```


Probably related to #1645 ?

### Additional contract requirements

When strict mode is enabled, an upload must still succeed when matching files are available to upload.
