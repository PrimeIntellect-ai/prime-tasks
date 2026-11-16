E0001 Error transforming template: Fn::ForEach could not be resolved
### CloudFormation Lint Version

0.87.4

### What operating system are you using?

Mac

### Describe the bug

When using `Fn::ForEach` with a dynamic value for the second argument (the value is determined via a !FindInMap call), it appears cfn-lint is not happy if second-level key in the !FindInMap call is of CF parameter type `AWS::SSM::Parameter::Value<String>`.  For e.g. below snippet

```
Parameters:
  Environment:
    Type: AWS::SSM::Parameter::Value<String>
    Description: Which Account type
    Default: /global/account/accounttype    # this value could be either of DEV/STG/PROD depending on AWS account where executed
    AllowedValues:
      - /global/account/accounttype

...
Mappings:
  Environments:
    DBInstances:  # no. of DB instances in Aurora cluster
      DEV: ['1']
      STG: ['1', '2']
      PROD: ['1', '2', '3']  # HA

...

  Fn::ForEach::DBInstances:
    - DBNum
    - !FindInMap [Environments, "DBInstances", !Ref Environment]
    - RDSDBInstance${DBNum}:
        Type: AWS::RDS::DBInstance
        Properties:
          Engine: !Ref Engine
          DBInstanceClass: db.serverless
          DBClusterIdentifier: !Ref RDSDBCluster
```

I am able to successfully create the desired stack with the above snippet (without cfn-lint validation), however cfn-lint validation fails against above code with the error `E0001 Error transforming template: Fn::ForEach could not be resolved`

If I change CF parameter `Environment` to type `String`, then cfn-lint validation succeeds.


### Expected behavior

cfn-lint is able to validate given code snippet without any issues

### Reproduction template

```
AWSTemplateFormatVersion: '2010-09-09'
Transform: 'AWS::LanguageExtensions'
Description: 'Aurora Serverless Cluster Stack'

Parameters:
  Environment:
    Type: AWS::SSM::Parameter::Value<String>
    Description: Which Account type
    Default: /global/account/accounttype
    AllowedValues:
      - /global/account/accounttype
    ConstraintDescription: Must be /global/account/accounttype
  DatabaseName:
    Type: String
    Description: Name of the Database
  DatabaseUsername:
    Type: String
    Description: The database username
  Engine:
    Description: Aurora Database engine
    Type: String
  EngineVersion:
    Description: Aurora Database engine version
    Type: String
  SnapshotId:
    Description: Pass in db snapshot when restoring or cloning a new db
    Type: String
    Default: ''   # no snapshot
  DeletionProtection:
    Type: String
    Description: Deletion Protection for the database cluster
  DatabaseDeletionPolicy:
    Type: String
    Description: Deletion Policy in case of stack deletion/updates
  MinCapacity:
    Type: Number
    Description: Minimum compute capacity for the database cluster
  MaxCapacity:
    Type: Number
    Description: Maximum compute capacity for the database cluster

Mappings:
  Config:
    DBInstances:  # no. of DB instances in Aurora cluster
      dev: ['1']
      stg: ['1', '2']
      prd: ['1', '2', '3']  # HA
  Iterator:
    Num:
      '1': 0
      '2': 1
      '3': 2

Conditions:
  SnapshotRestore: !Not [!Equals [!Ref SnapshotId, '']]

Resources:
  AuroraMasterSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub '${AWS::StackName}-db-credentials'
      Description: !Sub "This secret has a dynamically generated secret password for ${AWS::StackName} database"
      GenerateSecretString:
        SecretStringTemplate: !Join ['', ['{"username": "', !Ref DatabaseUsername, '"}']]
        GenerateStringKey: "password"
        PasswordLength: 15
        ExcludePunctuation: true
        ExcludeCharacters: '"@/\'

  RDSDBCluster:
    Type: AWS::RDS::DBCluster
    DeletionPolicy: !Ref DatabaseDeletionPolicy
    UpdateReplacePolicy: !Ref DatabaseDeletionPolicy
    Properties:
      Engine: !Ref Engine
      EngineVersion: !Ref EngineVersion
      EngineMode: provisioned   # serverless v2 uses 'provisioned' for 'EngineMode' attribute
      ServerlessV2ScalingConfiguration:
        MinCapacity: !Ref MinCapacity
        MaxCapacity: !Ref MaxCapacity
      DeletionProtection: !Ref DeletionProtection
      EnableHttpEndpoint: true   # serverless v2 postgresql supports Data API
      MasterUsername: !If
        - SnapshotRestore
        - !Ref "AWS::NoValue"
        - !Sub '{{resolve:secretsmanager:${AuroraMasterSecret}:SecretString:username}}'
      MasterUserPassword: !If
        - SnapshotRestore
        - !Ref "AWS::NoValue"
        - !Sub '{{resolve:secretsmanager:${AuroraMasterSecret}:SecretString:password}}'
      DBSubnetGroupName: test
      DatabaseName: !If [SnapshotRestore, !Ref "AWS::NoValue", !Ref DatabaseName]
      SnapshotIdentifier: !If [SnapshotRestore, !Ref SnapshotId, !Ref "AWS::NoValue"]
      BackupRetentionPeriod: 7
      StorageEncrypted: true
      VpcSecurityGroupIds: [sg-1234]

  Fn::ForEach::DBInstances:
    - DBNum
    - !FindInMap [Config, "DBInstances", !Ref Environment]
    - RDSDBInstance${DBNum}:
        Type: AWS::RDS::DBInstance
        Properties:
          Engine: !Ref Engine
          DBInstanceClass: db.serverless
          DBClusterIdentifier: !Ref RDSDBCluster
          AvailabilityZone: !Select [!FindInMap [Iterator, Num, !Ref DBNum], {Fn::GetAZs: ""}]
```
