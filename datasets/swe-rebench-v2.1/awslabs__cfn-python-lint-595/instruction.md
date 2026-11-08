Support for multiple CodePipeline OutputArtifacts
*cfn-lint version*: 0.12.1

*Description of issue.*

The CloudFormation linter does not yet support having multiple values for the OutputArtifacts property. When linting a template it gives the following error message:
`E2541 Action "CodeBuild" declares 2 OutputArtifacts which is not in expected range [0, 1].`

```yaml
---
AWSTemplateFormatVersion: 2010-09-09
Resources:
  Pipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      Name: pipeline
      RoleArn: 'rolearn'
      RestartExecutionOnUpdate: true
      ArtifactStore:
        Location: 'artifactbucket'
        Type: S3
      Stages:
        - Name: Source
          Actions:
            - Name: SourceRepo
              ActionTypeId:
                # More info on Possible Values: https://docs.aws.amazon.com/codepipeline/latest/userguide/reference-pipeline-structure.html#action-requirements
                Category: Source
                Owner: ThirdParty
                Provider: GitHub
                Version: "1"
              Configuration:
                Owner: '{{resolve:ssm:/service/github/owner:1}}'
                OAuthToken: '{{resolve:ssm:/service/github/token:3}}'
                Repo: 'repo'
                Branch: 'develop'
                PollForSourceChanges: true
              OutputArtifacts:
                - Name: source
              RunOrder: 1
        - Name: Build
          Actions:
            - Name: CodeBuild
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: "1"
              Configuration:
                ProjectName: 'codebuildproject'
              InputArtifacts:
                - Name: source
              OutputArtifacts:
                - Name: artifact1
                - Name: artifact2 # this goes wrong
              RunOrder: 1
```

As additional information a [blog post](https://aws.amazon.com/about-aws/whats-new/2018/08/aws-codebuild-adds-ability-to-create-build-projects-with-multiple-input-sources-and-output-artifacts/) about the release of support for this and the [CloudFormation spec](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-codepipeline-pipeline-stages-actions.html).
