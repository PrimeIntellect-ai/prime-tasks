prefixTemplate is ignored if nameTemplate is not specified
# This is a Bug Report

## Description

For bug reports:
* What went wrong?
I specified prefixTemplate in both the global section and definitions section and it appears to be ignored.  Alarms are still prefixed with the stack name.  If nameTemplate is specified, then the value is used.

* What did you expect should have happened?
The value of prefixTemplate changes my alarm names despite nameTemplate not being specified.

* What was the config you used?
```
custom:
  prune:
    automatic: true
    number: 5
  pythonRequirements:
    dockerizePip: non-linux
    layer:
      compatibleRuntimes:
        - python3.8
  alerts:
    prefixTemplate: my-prefix-${{self:provider.stage}}
    definitions:
      SQSErrorAlarm:
        prefixTemplate: my-prefix-${{self:provider.stage}}
         ...
```

* What stacktrace or error message from your provider did you see?
N/A

Similar or dependent issues:
* N/A

## Additional Data

* ***Serverless Framework Version***: 2.3.0
* ***Plugin Version***: 1.6.1
* ***Stack Trace***: N/A
* ***Provider Error messages***: N/A
