Support EventBridge Scheduler Service integration
# This is a Feature Proposal

## Description

Support Generation of proper permissions for this integration
* A Task that creates an EventBridge Scheduler Schedule fails to create IAM Statement in IAM Role.
* The `arn:aws:states:::aws-sdk:scheduler:createSchedule` resource should be supported

Similar or dependent issues:
* #432

### Additional contract requirements

- A Task whose Resource is `arn:aws:states:::aws-sdk:scheduler:createSchedule` must cause the generated IAM role policy to grant `scheduler:CreateSchedule`.
- That grant must be scoped to the schedules in the schedule group named by the Task's `GroupName` parameter. It must not be granted on all resources (`*`).
