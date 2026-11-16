Add ANSI escape support to `Kino.Text`
Currently, `Kino.Text` always renders as `Kino.Output.plain_text(content)`. To render text containing ANSI escape sequences, you have to create your own wrapper struct that uses `Kino.Output.text(content)`.

Being able to use `Kino.Text` to support text with ANSI escape sequences would be a nice little improvement:

```elixir
Kino.Text.new(my_text, plain: false) # default true
# or
Kino.Text.new(my_text, ansi: true) # default false
```
