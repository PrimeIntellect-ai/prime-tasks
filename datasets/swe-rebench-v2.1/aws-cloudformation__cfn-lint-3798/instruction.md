Enhance E1011 Message ( is too long)
### Is this feature request related to a new rule or cfn-lint capabilities?

rules

### Describe the feature you'd like to request

Fn::FindInMap, When the nested level depth is greater than 2 , error E1011 is thrown with a message xxx is too long (3).
Sample:
Mappings:
  MyCustomMap
     Level1:
        Level2:
           "key":"value"

Error message when cfn-lint is run
E1011  ['MyCustomMap',  'Level1',  'Level2',' Key'] is too long (3)
E3024 ['MyCustomMap', 'Level1',  'Level2', 'Key'] is too long (3)

### Describe the solution you'd like

Can the message be improved, to say "FindInMap only supports up to two levels of nesting for map lookups"

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request

### Would this feature include a breaking change?

- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

For an `Fn::FindInMap` lookup with more than two nested map-key levels (more than three items), the diagnostic should make clear that only two map-key levels are supported by stating the configured three-item maximum and the actual item count. The `maxItems` failure must use the format `expected maximum item count: {n}, found: {found}`, where `{n}` is the configured limit and `{found}` is the actual item count; no separate prose explanation is required. For this error, the function's validator name is `fn_findinmap`.
