The `inputFile` option crashes the process when the file path is missing
When passing a missing file path to the `inputFile` option, the process crashes.
This is because the `error` events from the streams created by the `inputFile` option are not handled.
