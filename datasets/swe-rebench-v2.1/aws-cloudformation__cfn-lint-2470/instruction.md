cfnlint via stdin has issues when parameters are present
### CloudFormation Lint Version

v0.70.1

### What operating system are you using?

Mac

### Describe the bug

```sh
echo 'Resources: {}' | cfn-lint --include-checks I
2022-11-03 11:14:45,106 - cfnlint.decode - ERROR - Template file not found: None
E0000 Template file not found: None
None:1:1
```

when no parameters:
```sh
echo '{"Resources": {}}' | cfn-lint
echo $?
0
```

### Expected behavior

```sh
echo 'Resources: {}' | cfn-lint --include-checks I
echo $?
0
```

### Reproduction template

```yaml
Resources: {}
```

```json
{
  "Resources": {}
}
```
