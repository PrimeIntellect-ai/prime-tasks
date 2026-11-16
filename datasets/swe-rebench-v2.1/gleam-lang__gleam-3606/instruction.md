Consider inserting `todo`s in incomplete `use` expressions when formatting.
A new user [recently confused](https://discord.com/channels/768594524158427167/1282783923100844064/1282783923100844064) (discord link) about some of the rules/differences between `let` expressions and `use` expressions. I think part of this confusion comes from being able to write a program like...
```gleam
fn example() {
  use x <- f
}
```
without the formatter inserting `todo`s when saving to indicate the expression is incomplete.

This behaviour already happens with `fn` expressions, and I think it would be both a nice QoL change and a better demonstration of the "use is just syntax sugar for callbacks" mantra that is often repeated.

### Additional contract requirements

When a `use` expression has following callback-body statements, formatting must preserve that body and must not add a `todo` merely because the `use` expression appears in the block.
