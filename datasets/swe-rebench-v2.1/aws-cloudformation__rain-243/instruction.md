rain fmt doesn't do round trip
rain fmt doesn't do a round trip with the `--unsorted` option.

Sample template:

```yaml
Parameters:
  RootId:
    Type: String

Resources:

  Sandbox:
    Type: AWS::Organizations::OrganizationalUnit
    Properties:
      ParentId: !Ref RootId
      Name: Sandbox
```

Command for round trip without `--unsorted`:

```bash
cat template.yaml | rain fmt --json | rain fmt
```

Result looks like YAML again (the keys remain unsorted in this case! Is that deliberate?).

```yaml
Parameters:
  RootId:
    Type: String

Resources:
  Sandbox:
    Type: AWS::Organizations::OrganizationalUnit
    Properties: {ParentId: !Ref "RootId", Name: Sandbox}
```

Command for round trip with `--unsorted`:

```bash
cat template.yaml | rain fmt --json --unsorted | rain fmt --unsorted
```

The result is technically YAML, but I was expecting it to be written on multiple lines!

```yaml
{Parameters: {RootId: {Type: String}}, Resources: {Sandbox: {Type: 'AWS::Organizations::OrganizationalUnit', Properties: {ParentId: !Ref "RootId", Name: Sandbox}}}}
```

### Additional contract requirements

- When formatting YAML, including with `--unsorted`, emit `Role: !Sub "arn:aws:iam::${AWS::AccountID}:role/lambda-basic"` as `Role: !Sub arn:aws:iam::${AWS::AccountID}:role/lambda-basic`.
- The round trip without `--unsorted` must produce block-style YAML rather than the compact JSON-style flow output; flow-style mappings must be expanded.
- The round trip with `--unsorted` must produce YAML written on multiple lines.
