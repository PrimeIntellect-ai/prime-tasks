CLI: add a way to set properties
E.g., with a repeatable arg:

```
rocrate add workflow foo.cwl -P name=Foo -P description='Lorem Ipsum'
```

### Additional contract requirements

- The `-P KEY=VALUE` option is repeatable and is accepted by every `rocrate add` subcommand: `file`, `dataset`, `workflow`, `test-suite`, `test-instance` and `test-definition`.
- Each `KEY=VALUE` pair is stored as a property of the entity being added: `-P name=foo` sets the entity's `name` and `-P description='foo bar'` sets its `description`.
