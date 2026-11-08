Blank tags property erroring in certain AWS regions
# This is a Bug Fix (kind of) and a Feature Proposal

## Description

For bug reports:
* What went wrong?
  * Compiled Cloudformation failed due to [Tags](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-stepfunctions-statemachine.html#cfn-stepfunctions-statemachine-tags) not being supported for StateMachines in some regions
* What did you expect should have happened?
  * Should have left out the [`Tags`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-stepfunctions-statemachine.html#cfn-stepfunctions-statemachine-tags) property if not provided
* What was the config you used?
  * Standard config that would work just fine in `us-east-1`, but _without_ tags
* What stacktrace or error message from your provider did you see?
  * The Cloudformation error stating that [`Tags`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-stepfunctions-statemachine.html#cfn-stepfunctions-statemachine-tags) is not a valid property

For feature proposals:
* What is the use case that should be solved. The more detail you describe this in the easier it is to understand for us.
  * If no tags are provided for a StateMachine, rather than add a `Tags` property with an [empty array](https://github.com/horike37/serverless-step-functions/blob/master/lib/deploy/stepFunctions/compileStateMachines.js#L210), don't include Tags at all. If Cloudformation in a specific region doesn't support Tags for a StateMachine, it will error even if provided an empty array
  * If a StateMachine has a property of `inheritGlobalTags` of `false`, _don't_ add the global tags to the specified state machine

* If there is additional config how would it look
  * For each StateMachine defined, add an optional boolean property of `inheritGlobalTags`

**I have a PR ready to address this issue**

## Additional Data
* ***Serverless Framework Core Version you're using***: 1.59.2
* ***The Plugin Version you're using***: 2.12.0
* ***Operating System***: MacOS Catalina 10.15.2
* ***Stack Trace***:
* ***Provider Error messages***: Property 'Tags' not a valid property
