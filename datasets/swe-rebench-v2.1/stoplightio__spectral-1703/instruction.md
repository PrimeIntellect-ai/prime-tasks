Incorrect line number when semicolons are present in a key
**Describe the bug**

The displayed line number for errors are always set to the line previous to one containing a semicolon in the key.

**To Reproduce**

Ruleset

```
rules:
  therule:
    description: schema type is array
    given: "$.paths[*].[*].responses[*].content[*].schema.type"
    then:
      function: pattern
      functionOptions:
        match: "array"
```

Document:

```
openapi: 3.0.3
paths:
  /customer:
    get:
      responses:
        "200":
          content: # recieves error on this line
            application/json;charset=utf-8: # semicolon causes the problem
              schema:
                type: string # expecting error on this line
```

**Expected behavior**

Error should be on line 10 (type).

**Actual behavior**

Error shows up on line 7 (content), right before the key including a semicolon.

**Environment (remove any that are not applicable):**

- Library version: 5.9.1

**Additional comments**

We have tried enclosing the key in double quotations which gave no difference in result.
