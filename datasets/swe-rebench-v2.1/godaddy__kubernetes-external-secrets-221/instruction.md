2.2.0 Failing with TypeError: Cannot destructure property `versionStage` of 'undefined' or 'null'.
@furikake @Flydiverny 2.2.0 poller is failing for ExternalSecrets WITHOUT the new `versionStage` property with error:
`TypeError: Cannot destructure property `versionStage` of 'undefined' or 'null'.`

I will open a PR if I fix it locally.

### Additional contract requirements

The poller must process an ExternalSecret that has no `versionStage` property without failing with the reported TypeError.
