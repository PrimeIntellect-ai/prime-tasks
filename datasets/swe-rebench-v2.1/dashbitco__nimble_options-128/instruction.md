A question on error message of `validate/2`
When trying the example code in `README.md`:

```elixir
definition = [
  connections: [
    type: :non_neg_integer,
    default: 5
  ],
  url: [
    type: :string,
    required: true
  ]
]

options = []
NimbleOptions.validate(options, definition)
```

It returns:
```elixir
{:error,
 %NimbleOptions.ValidationError{
   message: "required :url option not found, received options: [:connections]",
   key: :url,
   value: nil,
   keys_path: []
 }}
```

We provide `options` as `[]`,

But, the `message:` line shows that the received options are `[:connections]`.

---

It seems that the received options considers the default values, but should we consider the default values when showing the received options?

### Additional contract requirements

- When a required option is missing, the `received options` in the validation error message must list only keys supplied in the original options, excluding keys added from schema defaults. For `NimbleOptions.validate([], [age: [type: :non_neg_integer, default: 10], name: [type: :string, required: true]])`, the message must be `required :name option not found, received options: []`.
