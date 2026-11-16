serverless-domain-manager
Is domain manager supported?

Have tried getting alias plugin running in existing stack, but not getting far.

The CloudFormation template is invalid: Template format error: Unresolved resource dependencies [ApiGatewayDeployment1521079052823] in the Resources block of the template


#66 looks similar, where the suggestion is to locate unsupported resources. Im wondering if its the basepath mapping resource that's causing issues.

### Additional contract requirements

- When alias processing encounters an API Gateway `BasePathMapping`, preserve the mapping in an output CloudFormation template. It may be in either output stack.
- Do not emit an unresolved `DependsOn` reference to an API Gateway deployment in either output template.
