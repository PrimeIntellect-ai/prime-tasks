Notifications for SNS topics
Add notification configuration for SNS topics that are created by the plugin.

### Additional contract requirements

- For a plugin-created SNS topic with no configured notifications, include `Subscription: []` in its CloudFormation `Properties`.
- A topic entry may be an object containing `topic` and a `notifications` array. Each notification has `protocol` and `endpoint`; include a corresponding item with `Protocol` and `Endpoint` in the created topic's CloudFormation `Properties.Subscription`.
