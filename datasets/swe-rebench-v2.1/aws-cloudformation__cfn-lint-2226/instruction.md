construct_yaml_map leading to TypeError: unhashable type: 'dict_node'
*cfn-lint version: 0.58.1*

*Unhandled `TypeError: unhashable type: 'dict_node'` thrown from construct_yaml_map.*

Please provide as much information as possible:
Utilising some slightly edited form of the example eks-nodegroup cfn, [see here for the failing cfn](https://github.com/SaltKhan/_cfn-breaking-cfn-lint/blob/main/eks-nodegroup.yaml) or [here, for the stacktrace](https://github.com/SaltKhan/_cfn-breaking-cfn-lint/blob/main/README.md). The problem occurrs on line 259 `VPCZoneIdentifier: !Join [ ',', [ !ImportValue Fn::Sub: "${NetworkStackName}-SubnetsPrivate01", !ImportValue Fn::Sub: "${NetworkStackName}-SubnetsPrivate02" ] ]`. (Was trying to provide a list by string concat as that's what's listed as the example input when subnets is a parameter as in the example cfn, but I've changed that for the example I provide here.) I changed the line to an expanded `!Join` ~
```
      VPCZoneIdentifier: !Join
                           - ','
                           - - Fn::ImportValue: !Sub "${NetworkStackName}-SubnetsPrivate01"
                             - Fn::ImportValue: !Sub "${NetworkStackName}-SubnetsPrivate02"
```
And it now correctly yields a normal error, rather than hitting the exception.
I found this similar previous issue ~ https://github.com/aws-cloudformation/cfn-lint/issues/348
