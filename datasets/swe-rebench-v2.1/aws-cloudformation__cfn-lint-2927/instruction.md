`I3037` false positives in `AWS::ECS::TaskDefinition.ContainerDefinitions.Command`
### CloudFormation Lint Version

0.83.0

### What operating system are you using?

Mac

### Describe the bug

`I3037` issues (*List has a duplicate value*) are reported if the command specified in `AWS::ECS::TaskDefinition.ContainerDefinitions.Command` has repeating entries, e.g. the values of several command arguments are the same.

### Expected behavior

No issue is detected.

### Reproduction template

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "This template deploys an ECS task definition.",
  "Resources": {
    "MyECSTaskDefinition": {
      "Type": "AWS::ECS::TaskDefinition",
      "Properties": {
        "ContainerDefinitions": [
          {
            "Command": [
              "do_something",
              "--foo",
              "1",
              "--bar",
              "1"
            ],
            "Image": "my-image",
            "Name": "my-task"
          }
        ]
      }
    }
  }
}
```
