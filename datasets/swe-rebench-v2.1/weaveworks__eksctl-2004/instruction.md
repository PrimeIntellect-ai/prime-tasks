Support for Pre bootstrap commands in Unmanaged Windows Node Groups
**Why do you want this feature?**

For Linux Node groups, `preBootstrapCommands` can be used to run custom scripts/commands at instance start up. But the same is not possible for windows instances. Some uses cases for this would be:

- Setting the instance pagefile size
- Installing & configuring the [cloudwatch agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/download-cloudwatch-agent-commandline.html) for instance metrics collection.


**What feature/behavior/change do you want?**

- Allow `preBootstrapCommands` command (Powershell commands) for windows node groups and add it it as a part of the instance user data.
