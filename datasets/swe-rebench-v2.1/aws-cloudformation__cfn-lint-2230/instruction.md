[New Rule] BackupPlan Lifecycle cold to delete minimum difference
*cfn-lint version:* 0.58.2

*Description of issue.*
In CloudFormation, when deploying a stack with an `AWS::Backup::BackupPlan` lifecycle rule to age off data after moving it to cold storage, the deployment will fail if the `DeleteAfterDays` value is less than 90 days apart from the `MoveToColdStorageAfterDays` period.

As an example:
<details>
  <summary>Example failing backup plan</summary>
  CloudFormation error:

![image](https://user-images.githubusercontent.com/1835431/156852439-202a56a9-e9ca-4cb5-8cdb-3ed19e87d80b.png)

  Example resource:
  ```yaml
  BackupPlan:
    Type: AWS::Backup::BackupPlan
    DeletionPolicy: Delete
    UpdateReplacePolicy: Delete
    Properties:
      BackupPlan:
        BackupPlanName: "invalid-backup-plan"
        BackupPlanRule:
          - RuleName: "invalid-rule"
            TargetBackupVault: !Ref BackupVault
            ScheduleExpression: "cron(0 0 ? * MON *)"
            Lifecycle:
              MoveToColdStorageAfterDays: 7
              DeleteAfterDays: 30
  ```
</details>
Currently this is not picked up by `cfn-lint`.
<hr><br>
I've opened a PR at #2230 to add in a rule that I think would resolve it, but not entirely sure on the process of adding a brand new rule / service to `cfn-lint`, so please shout if there's anything missing or extra to do. Thanks!
