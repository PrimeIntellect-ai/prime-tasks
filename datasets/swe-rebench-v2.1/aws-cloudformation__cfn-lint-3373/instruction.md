AWS::CodePipeline::Pipeline Fn::GetAtt passes Version as String not Integer
### CloudFormation Lint Version

cfn-lint 1.3.2

### What operating system are you using?

Windows, Ubuntu

### Describe the bug

Using the AWS provided code https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-codepipeline-webhook.html `!GetAttWebhookPipeline.Version` is called. https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-codepipeline-pipeline.html says it is a number however cfn-lint returns `E1010 {'Fn::GetAtt': ['CodePipelineForIntegTest', 'Version']} is not of type 'integer'
`



### Expected behavior

I would expect AWS code samples to pass without errors when tested with cfn-lint given that the code works without error.

### Reproduction template

```
---
AWSTemplateFormatVersion: 2010-09-09
Description: CodePipeline sample
Parameters:
  CodePipelineServiceRole:
    Type: String
  ArtifactStoreS3Location:
    Type: String
  SourceActionName:
    Type: String


Resources:
  Webhook:
    Type: AWS::CodePipeline::Webhook
    Properties:
      AuthenticationConfiguration:
        SecretToken: "{{resolve:secretsmanager:MyGitHubSecret:SecretString:token}}"
      Filters:
        - JsonPath: "$.ref"
          MatchEquals: refs/heads/{Branch}
      Authentication: GITHUB_HMAC
      TargetPipeline:
        Ref: CodePipelineForIntegTest
      TargetAction: Source
      Name: MyWebhook
      TargetPipelineVersion:
        Fn::GetAtt:
          - CodePipelineForIntegTest
          - Version
      RegisterWithThirdParty: 'true'


  CodePipelineForIntegTest:
    Type: 'AWS::CodePipeline::Pipeline'
    Properties:
      RoleArn: !Ref CodePipelineServiceRole
      Stages:
        - Name: Source
          Actions:
            - Name: !Ref SourceActionName
              InputArtifacts: [ ]
              ActionTypeId:
                Category: Source
                Owner: AWS
                Version: '1'
                Provider: CodeStarSourceConnection
              OutputArtifacts:
                - Name: SourceOutput
              Configuration:
                BranchName: main
                ConnectionArn: >-
                  arn:aws:codestar-connections:us-east-1:123456789123:connection/id
                FullRepositoryId: repo-owner/sample-project
              RunOrder: 1
        - Name: Beta
          Actions:
            - Name: BetaAction
              InputArtifacts:
                - Name: SourceOutput
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: Sample
              RunOrder: 1
      Triggers:
        - ProviderType: CodeStarSourceConnection
          GitConfiguration:
            Push:
              - Tags:
                  Excludes:
                    - beta-*
                  Includes:
                    - release-*
              - Branches:
                  Excludes:
                    - beta-*
                  Includes:
                    - release-*
                FilePaths:
                  Includes:
                    - projectA/**
                    - common/**/*.js
                  Excludes:
                    - '**/README.md'
                    - '**/LICENSE'
                    - '**/CONTRIBUTING.md'
            PullRequest:
              - Branches:
                  Excludes:
                    - stable-v1-*
                  Includes:
                    - stable-*
                    - release-*
                FilePaths:
                  Includes:
                    - projectA/**
                    - common/**/*.js
                  Excludes:
                    - '**/README.md'
                    - '**/LICENSE'
                    - '**/CONTRIBUTING.md'
                Events:
                  - CLOSED
            SourceActionName: !Ref SourceActionName
      PipelineType: V2
      ExecutionMode: PARALLEL
      ArtifactStore:
        Type: S3
        Location: !Ref ArtifactStoreS3Location

```
