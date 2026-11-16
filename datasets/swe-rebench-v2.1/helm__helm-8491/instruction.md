The sdk dependency manager error refers to Helm CLI
Output of `helm version`: v3.4.0 development and previous v3 releases

The download manager within the SDK notes... https://github.com/helm/helm/blob/6a536661fcf1dc0315798ece70bbf193e725945c/pkg/downloader/manager.go#L414

The SDK should have an error that's general and the CLI code in the cmd directory should detect it and decorate with any CLI related elements. Separation of concerns and all.
