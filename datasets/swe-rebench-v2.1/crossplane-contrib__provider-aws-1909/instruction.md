RDSInstance can't get into Sync=True state with an warning  'api error InvalidParameterCombination: No modifications were requested'
### What happened?

RDSInstance MR can't get into `SYNC=True` state
This issue might be related to: #1795


### How can we reproduce it?
I have below RDS Instance MR
```
apiVersion: database.aws.crossplane.io/v1beta1
kind: RDSInstance
metadata:
  annotations:
    crossplane.io/composition-resource-name: rds
    crossplane.io/external-name: us1-ekswac001-rdswac001
  creationTimestamp: "2023-03-23T14:43:16Z"
  finalizers:
  - finalizer.managedresource.crossplane.io
  generateName: wac-ekswac001-rdswac001-
  generation: 129675
  labels:
    crossplane.io/claim-name: ekswac001-rdswac001
    crossplane.io/claim-namespace: wac
    crossplane.io/composite: ekswac001-rdswac001-4tshm
  name: wac-ekswac001-rdswac001-h58tx
  ownerReferences:
  - apiVersion: rds.aws.crossplane.sinch.com/v1alpha1
    blockOwnerDeletion: true
    controller: true
    kind: XMySQLInstance
    name: ekswac001-rdswac001-4tshm
    uid: a8211232-ea1e-429e-b477-ebfbecc20058
  resourceVersion: "446399353"
  uid: 05a94c62-ddaf-4ee7-b885-a3704f782091
spec:
  deletionPolicy: Orphan
  forProvider:
    allocatedStorage: 333
    applyModificationsImmediately: false
    autoMinorVersionUpgrade: true
    availabilityZone: us-east-1a
    backupRetentionPeriod: 1
    caCertificateIdentifier: rds-ca-2019
    copyTagsToSnapshot: true
    dbInstanceClass: db.r5.4xlarge
    dbName: db
    dbParameterGroupName: rdswac001-db-parameter-group
    dbSubnetGroupName: private_subnets_vpc-xxx
    deletionProtection: false
    enableCloudwatchLogsExports:
    - audit
    enableIAMDatabaseAuthentication: false
    enablePerformanceInsights: true
    engine: mysql
    engineVersion: 5.7.38
    kmsKeyId: 6a1a9e12-xxx-xxx-xxx-xxx
    licenseModel: general-public-license
    masterPasswordSecretRef:
      key: password
      name: ekswac001-rdswac001-master-password
      namespace: wac
    masterUsername: root
    maxAllocatedStorage: 1000
    monitoringInterval: 60
    monitoringRoleArn: arn:aws:iam::xxx:role/rds-monitoring-role
    multiAZ: true
    optionGroupName: sinch-default-mysql-5-7
    performanceInsightsKMSKeyId: arn:aws:kms:us-east-1:xxx:key/6a1a9e12-xxx-xxx-xxx-xxx
    performanceInsightsRetentionPeriod: 7
    port: 3306
    preferredBackupWindow: 14:00-16:00
    preferredMaintenanceWindow: mon:02:30-mon:03:00
    publiclyAccessible: false
    region: us-east-1
    skipFinalSnapshotBeforeDeletion: true
    storageEncrypted: true
    storageType: gp2
    tags:
    - key: crossplane-kind
      value: rdsinstance.database.aws.crossplane.io
    - key: crossplane-name
      value: wac-ekswac001-rdswac001-h58tx
    - key: crossplane-providerconfig
      value: crossplane-provider-aws
    vpcSecurityGroupIds:
    - sg-0fxxx
    - sg-09xxx
  providerConfigRef:
    name: crossplane-provider-aws
  publishConnectionDetailsTo:
    configRef:
      name: default
    metadata:
      labels:
        secret.crossplane.io/owner-uid: 05a94c62-ddaf-4ee7-b885-a3704f782091
    name: wac-ekswac001-rdswac001-rdsinstance
status:
  atProvider:
    allocatedStorage: 333
    backupRetentionPeriod: 1
    dbInstanceArn: arn:aws:rds:us-east-1:xxx:db:us1-ekswac001-rdswac001
    dbInstanceStatus: available
    dbParameterGroups:
    - dbParameterGroupName: rdswac001-db-parameter-group
      parameterApplyStatus: in-sync
    dbResourceId: db-xxx
    dbSubnetGroup:
      dbSubnetGroupDescription: This is a private subnet group for AWS RDS instances.
        Only containing our regular private subnets in vpc-xxx
      dbSubnetGroupName: private_subnets_vpc-xxx
      subnetGroupStatus: Complete
      subnets:
      - subnetAvailabilityZone:
          name: us-east-1c
        subnetIdentifier: subnet-5xxx
        subnetStatus: Active
      - subnetAvailabilityZone:
          name: us-east-1b
        subnetIdentifier: subnet-0xxx
        subnetStatus: Active
      - subnetAvailabilityZone:
          name: us-east-1a
        subnetIdentifier: subnet-exxx
        subnetStatus: Active
      vpcId: vpc-xxx
    endpoint:
      address: us1-ekswac001-rdswac001.xxx.us-east-1.rds.amazonaws.com
      hostedZoneId: Z2R2ITUGPM61AM
      port: 3306
    enhancedMonitoringResourceArn: arn:aws:logs:us-east-1:xxx:log-group:RDSOSMetrics:log-stream:db-xxx
    instanceCreateTime: "2022-08-04T06:34:53Z"
    latestRestorableTime: "2023-08-30T11:00:00Z"
    optionGroupMemberships:
    - optionGroupName: sinch-default-mysql-5-7
      status: in-sync
    pendingModifiedValues:
      pendingCloudwatchLogsExports: {}
    performanceInsightsEnabled: true
    secondaryAvailabilityZone: us-east-1c
    vpcSecurityGroups:
    - status: active
      vpcSecurityGroupId: sg-0fxxx
    - status: active
      vpcSecurityGroupId: sg-09xxx
  conditions:
  - lastTransitionTime: "2023-07-18T04:28:07Z"
    message: 'update failed: cannot modify RDS instance: api error InvalidParameterCombination:
      No modifications were requested'
    reason: ReconcileError
    status: "False"
    type: Synced
  - lastTransitionTime: "2023-06-02T06:06:53Z"
    reason: Available
    status: "True"
    type: Ready
```

I get an event `cannot modify RDS instance: api error InvalidParameterCombination: No modifications were requested`:
```
kubectl describe rdsinstances.database.aws.crossplane.io wac-ekswac001-rdswac001-h58tx
Events:
  Type     Reason                        Age                    From                                            Message
  ----     ------                        ----                   ----                                            -------
  Warning  CannotUpdateExternalResource  79s (x9917 over 3d1h)  managed/rdsinstance.database.aws.crossplane.io  cannot modify RDS instance: api error InvalidParameterCombination: No modifications were requested
```

In AWS CloudTrail I can see:
```
    "errorCode": "InvalidParameterCombinationException",
    "errorMessage": "No modifications were requested",
    "requestParameters": {
        "allowMajorVersionUpgrade": false,
        "dBInstanceIdentifier": "us1-ekswac001-rdswac001",
        "applyImmediately": false
    },
```

Provider Logs
```
kubectl logs -n crossplane-system pod/crossplane-provider-aws-447dacb385f5-d6f4645df-6rqfx

{"level":"info","ts":"2023-09-04T09:53:00.064Z","logger":"provider-aws","msg":"Alpha feature enabled","flag":"EnableAlphaExternalSecretStores"}
Setup endpointgroup
W0904 09:53:00.918953       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 09:53:00.920521       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
[controller-runtime] log.SetLogger(...) was never called, logs will not be displayed:
goroutine 3936 [running]:
runtime/debug.Stack()
        runtime/debug/stack.go:24 +0x65
sigs.k8s.io/controller-runtime/pkg/log.eventuallyFulfillRoot()
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/log/log.go:59 +0xbd
sigs.k8s.io/controller-runtime/pkg/log.(*delegatingLogSink).WithValues(0xc0008d2080, {0xc0065effa0, 0x2, 0x2})
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/log/deleg.go:168 +0x54
github.com/go-logr/logr.Logger.WithValues(...)
        github.com/go-logr/logr@v1.2.4/logr.go:323
sigs.k8s.io/controller-runtime/pkg/builder.(*Builder).doController.func1(0xc0065eff80)
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/builder/controller.go:398 +0x182
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).reconcileHandler(0xc0005fbf40, {0x749d9a0, 0xc0004b9700}, {0x625de60?, 0xc0065eff60?})
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/internal/controller/controller.go:305 +0x1b9
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).processNextWorkItem(0xc0005fbf40, {0x749d9a0, 0xc0004b9700})
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/internal/controller/controller.go:265 +0x1d9
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2.2()
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/internal/controller/controller.go:226 +0x85
created by sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2
        sigs.k8s.io/controller-runtime@v0.15.0/pkg/internal/controller/controller.go:222 +0x333
W0904 10:02:47.922518       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:07:48.924422       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:12:54.926296       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:19:22.928934       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:26:00.932433       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:32:34.934234       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:38:29.935659       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:45:13.940025       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:52:38.941015       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 10:59:48.944220       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:09:45.946386       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:16:10.949184       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:26:01.952099       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:32:02.953704       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:41:57.955356       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:47:20.957188       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 11:53:46.958749       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:01:47.962187       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:09:17.964217       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:16:02.967047       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:22:45.968958       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:27:48.970744       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:34:03.973531       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:41:08.975225       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
W0904 12:48:53.978472       1 warnings.go:70] BucketPolicy has been deprecated. Use spec.forProvider.policy in Bucket instead.
```

### What environment did it happen in?
Crossplane version: `1.13.2`
provider-aws: `0.43.0`

### Additional contract requirements

The reconciliation failure is caused by the provider treating a difference in
`spec.forProvider.availabilityZone` as a pending modification for an RDS
instance that is a MultiAZ deployment, even though AWS ignores `AvailabilityZone`
for MultiAZ instances and rejects a modification request that carries no other
changes with `InvalidParameterCombination: No modifications were requested`.
The fix must make the provider ignore that difference.

In `pkg/clients/database`:

- `CreatePatch` must not include `AvailabilityZone` in the returned patch when
  the desired parameters set `MultiAZ` to `true`, or when the observed
  `DBInstance` has `MultiAZ` set to `true`. A difference in `AvailabilityZone`
  alone must therefore produce an empty patch.
- `IsUpToDate` must return `true` when the only difference between the desired
  parameters and the observed instance is `AvailabilityZone` and the instance is
  a MultiAZ deployment.
- For instances that are not MultiAZ, an `AvailabilityZone` difference must
  still be reported in the patch as before.
