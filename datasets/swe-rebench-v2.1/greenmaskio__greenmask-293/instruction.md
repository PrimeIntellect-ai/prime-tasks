Feat: Replace transformer with dynamic value
As discussed in [Discord](https://discord.com/invite/rKBKvDECfd), it would be useful to have a Replace transformer that supports dynamic values. In this case, the replacement value could be taken from another column.

For example
```
- name: "RandomWord"
    params:
       column: "name"

- name: "Replace"
    params:
       column: "name_2"
    dynamic_params:
        value:
          column: "name"

- name: "Replace"
    params:
       column: "name_3"
    dynamic_params:
        value:
          column: "name"
```

Thanks @edarchis for the idea — I've added it to the backlog!

### Additional contract requirements

- When `validate` is enabled and a dynamic replacement value fails type validation, return an error containing `dynamic value validation error`.
