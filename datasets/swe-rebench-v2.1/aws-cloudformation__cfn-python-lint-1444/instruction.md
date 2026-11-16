Unexpected E1029 error
*cfn-lint version: (0.29.1)*

*Description of issue.*

After this version was released, I started getting an error when linting a template.  This error specific to `BuildSpec` attributes for a `AWS::CodeBuild::Project` project.

    E1029 Found an embedded parameter outside of an "Fn::Sub" at
    Resources/MyCodeBuild/Properties/Source/BuildSpec
    cloudformation.json:151:11

I mocked up a JSON template that showcases the problem and [attached](https://github.com/aws-cloudformation/cfn-python-lint/files/4383494/cloudformation.txt) it.
