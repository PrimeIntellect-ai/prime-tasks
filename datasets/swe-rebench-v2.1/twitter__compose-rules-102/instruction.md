Allow reporting PreviewPublic for @Preview Composables without any param
Currently the `PreviewPublic` rule only reports Composable functions that are annotated with `@Preview` and [have preview params](https://github.com/twitter/compose-rules/blob/020b077cc5df7bcb85c46d00c1e3474aa72dd6b3/rules/common/src/main/kotlin/com/twitter/compose/rules/ComposePreviewPublic.kt#L21).
In our codebase we always wrap the actual Composables into separate Preview Composables (e.g. to set a specific theme). Therefore Composables annotated with`@Preview` are solely used as previews and should never be used in actual UI. Currently this rule won't report these functions.

Would be nice to allow configuring this rule, so that also Composable functions annotated with `@Preview` and **without any params** are reported.

### Additional contract requirements

Provide a configuration option named `previewPublicOnlyIfParams`. It is enabled by default: public composables annotated with `@Preview` are reported only when they have preview parameters. When set to `false`, public composables annotated with `@Preview` are reported whether or not they have parameters.
