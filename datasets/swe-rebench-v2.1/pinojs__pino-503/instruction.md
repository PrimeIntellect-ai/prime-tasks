Custom label for level
At first glance it looks like https://github.com/pinojs/pino/blob/master/lib/levels.js#L29-L42 is where the labels are set.

Some of my destinations use the label `severity` instead of `level`. Is there any way at the moment to configure this? Is a PR to add this feature welcome?

### Additional contract requirements

- Support a string logger configuration option named `changeLevelName` that replaces `level` as the key for the emitted level value. It defaults to `level`; the value is numeric unless `useLevelLabels` is enabled, in which case it is the level label.
