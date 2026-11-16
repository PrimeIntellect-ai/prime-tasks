fmt adds newlines to multiline comments
I believe YAML technically does not have "multiline" comments, but below behavior strikes me as unintended.

```
---
Conditions:
  NeverValid: !Equals [True, False]

# Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
# tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
# quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
# consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
# cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non
# proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
Resources:
  NullResource:
    Type: 'Custom::NullResource'
    Condition: NeverValid
```

```
% diff -y null_template.yaml <(rain fmt null_template.yaml)
---                                                           <
Conditions:                                                     Conditions:
  NeverValid: !Equals [True, False]                               NeverValid: !Equals [True, False]

# Lorem ipsum dolor sit amet, consectetur adipiscing elit, se   # Lorem ipsum dolor sit amet, consectetur adipiscing elit, se
                                                              >
# tempor incididunt ut labore et dolore magna aliqua. Ut enim   # tempor incididunt ut labore et dolore magna aliqua. Ut enim
                                                              >
# quis nostrud exercitation ullamco laboris nisi ut aliquip e   # quis nostrud exercitation ullamco laboris nisi ut aliquip e
                                                              >
# consequat. Duis aute irure dolor in reprehenderit in volupt   # consequat. Duis aute irure dolor in reprehenderit in volupt
                                                              >
# cillum dolore eu fugiat nulla pariatur. Excepteur sint occa   # cillum dolore eu fugiat nulla pariatur. Excepteur sint occa
                                                              >
# proident, sunt in culpa qui officia deserunt mollit anim id   # proident, sunt in culpa qui officia deserunt mollit anim id
                                                              >
Resources:                                                      Resources:
  NullResource:                                                   NullResource:
    Type: 'Custom::NullResource'                              |     Type: Custom::NullResource
    Condition: NeverValid                                           Condition: NeverValid
```

### Additional contract requirements

- In the formatted output, place `foo: bar # Comment about foo:bar` immediately after `# Comment about the doc`, with no blank line between them, and include a blank line immediately before `# Comment about grault`.
