DatapointsToAlarm auto matches the EvaluationPeriod value - No way to update currently
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a (Bug Report / Feature Proposal)

## Description

For bug reports:
* What went wrong?
When using the plugin to update the Evaluation Period it automatically set the Datapoints To Alarm equal to the value for the Evaluation Period.
* What did you expect should have happened?
I would have expected the Datapoints To Alarm value to remain 1 unless otherwise specified.
* What was the config you used?
In serverless.yml I had the `functionErrors` section with the following values:
```
functionErrors:
        period: 60
        evaluationPeriods: 5
        threshold: 1
```
* What stacktrace or error message from your provider did you see?
There were no errors, however this change would never trigger any alarms with a DatapointsToAlarm value also equal to 5.

For feature proposals:
* What is the use case that should be solved. The more detail you describe this in the easier it is to understand for us.
[HIDDEN]
* If there is additional config how would it look
Tests and Readme would also need updates with the new alarm value.

Similar or dependent issues:
* N/A

## Additional Data

* ***Serverless Framework Version***: 1.26.1
* ***Stack Trace***:
* ***Provider Error messages***:

### Additional contract requirements

- The alarm configuration accepts a numeric `datapointsToAlarm` value that controls how many datapoints within the evaluation window must breach the threshold before the alarm fires, independent of `evaluationPeriods`.
- The generated CloudWatch alarm resource exposes this value under the property name `DatapointsToAlarm`.
- Every built-in alarm definition defaults `datapointsToAlarm` to `1`.
