Incorrect rule: "E1019: Sub parameter should be an object of 1 or string for..."
*cfn-lint version: 0.40.0*

I am getting an incorrect error that [`E1019`](https://github.com/aws-cloudformation/cfn-python-lint/blob/master/docs/rules.md#E1019)` Sub parameter should be an object of 1 or string for...` when using YAML:

```
        - Fn::Sub:
            - 'example-${Var}-${Var2}'
            - Var: 123
              Var2: 456
```

Official docs: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-sub.html

Official docs sample:
```
Fn::Sub:
  - String
  - Var1Name: Var1Value
    Var2Name: Var2Value
```
