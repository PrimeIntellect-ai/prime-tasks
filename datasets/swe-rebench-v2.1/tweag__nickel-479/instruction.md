[Dogfooding] Escaping enums
**Is your feature request related to a problem? Please describe.**
While dogfooding on the [mantis repo](https://github.com/input-output-hk/mantis-ops), there are several fields with a finite say of strings as possible values (ex: [here](https://github.com/input-output-hk/mantis-ops/blob/81ad4cb0ec5ff9faeb9065a2ddac060cef6452ac/schemas/nomad/types.cue#L54)). It's nice to represent this type/contract with enums in Nickel, like:

```
{
  protocol | <http, ftp, https>
}
```

As the typechecker is then aware of those, can check match exhaustiveness, and so on. However it isn't possible when one of the alternative is not syntactically an identifier.

**Describe the solution you'd like**
Having a way of escaping non-identifier characters inside enum tags, e.g. by surrounding them by quotes:

```
{
  operator | <"Foo!bar", "Foo!baz", "!="> = `"Foo!bar",
}
```

**Describe alternatives you've considered**
We can also encode this using a custom contract (most probably, this kind of combinator will be in the stdlib at some point):

```
let IsIn = fun values label value =>
  if lists.elem value values then
    value
  else
    contracts.blame label
in
{
  operator | #(IsIn ["Foo!bar", "Foo!baz", "!="])
}
```

But:

1. It is less consistent (some enums will be defined with the builtin type, some others with this custom contracts, without beginners knowing why, maybe)
2. As mentioned, the typechecker don't know what to do with that (no match, no typechecking, no pattern matching exhaustiveness, etc.)

A counter-argument could be that enums are meant for things that resembles simple labels, and if one of the alternative for a field is `"!="`, then maybe it shouldn't be encoded as an enum to begin with.

### Additional contract requirements

- An enum tag may be written either as a bare identifier or as a quoted string
  literal, e.g. `` `"Foo!bar" `` or `` `"!=" ``. Quoting is what makes it
  possible to use tags containing characters that are not valid in an
  identifier.
- Enum type rows may use quoted tags as well, e.g. `<"foo:baz", "bar:baz">` and
  `forall r. <"foo:baz", "bar:baz" | r>`.
- In a `switch` expression, every case tag is written with a leading backtick,
  whether the tag is a bare identifier or a quoted string, e.g.
  `switch { `foo => 1, `"bar:baz" => 2, _ => 3 }`. A `switch` case tag written
  without the leading backtick is not valid syntax.
