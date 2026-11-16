Nested each broken in 2.0.0
I have some template that look like this:

```
{{#each protocol.classes as |class| ~}}
{{#each class.methods as |method| ~}}
{{method.id}}
{{/each ~}}
{{/each ~}}
```

With data that look like this (passed as "protocol" to the template):

```
{
  "classes": [
    {
      "methods": [
        "id": 1
      ]
    }
  ]
}
```

This works fine with handlebars 2.0.0-beta.2 but fails with 2.0.0
