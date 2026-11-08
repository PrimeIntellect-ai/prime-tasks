Whitespace issue with if conditions
Askama seems to be including whitespace from inside an if condition even when the condition is not fulfilled. Here is my template file:

```jinja
{%- if some_condition -%}
# WARNING

{% endif -%}

# FILE START
```

What I expected is:

- When `some_condition` is `true`:

  ```
  # WARNING

  # FILE START
  ```

- When `some_condition` is `false`:

  ```
  # FILE START
  ```

What I got is:

- When `some_condition` is `true`: same as expected output
- When `some_condition` is `false` (notice the blank lines before `FILE START`):

  ```


  # FILE START
  ```

Is this a bug? If not, is there a way to get the behaviour I described?
