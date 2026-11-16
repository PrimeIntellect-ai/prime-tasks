Add support for cmd and args when creating a new service
## In what area(s)?
Classifications:
/kind good-first-issue
/kind feature
/kind proposal

## Describe the feature:

Knative, via yaml, supports specifying the cmd and args in the podSpec - kn should support this too since there are times when people may need to specify which exe in the image to run or what args to pass to the exe. Sometimes the default values in the image are not sufficient.

### Additional contract requirements

The service-create command exposes `--cmd` to specify the container command and a repeatable `--arg` option to specify its arguments.
