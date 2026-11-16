If constraint_message includes a ${} reference and no translations, expanded XPath path should be in <output>
#### Software and hardware versions
pyxform v1.x.x, Python v1.2.0

#### Problem description
If a form only uses one language and has a `constraint_message` with a ${} reference, no `output` is generated. This is a side effect of https://github.com/XLSForm/pyxform/issues/285.

#### Steps to reproduce the problem
1. Build a single-language form with a constraint message that has a ${} reference in it:

type | name | label | constraint | constraint_message
-- | -- | -- | -- | --
select_one fruits | Q1 | Select the fruit that you like the most: |   |
select_one fruits | Q2 | Select (again) the (same) fruit that you like the most (that   you selected in Q1): | .=${Q1} | You chose ${Q1} in Q1 but now it's different!

1. Convert it and see that the constraint message is set to `jr:constraintMsg="You chose  /data/Q1  in Q1 but now it's different!"`. This means the `/data/Q1` reference is not evaluated by clients.

#### Expected behavior
`/data/Q1` gets evaluated by clients.

#### Other information
A form design workaround is to set a language for the `constraint_message` column to force the generation of an `itext` block. [HIDDEN]

### Additional contract requirements

- In a single-language form, a `${}` reference in a `constraint_message` must be evaluated by clients. The expanded XPath path must appear in an `<output value="..."/>` element in the generated message value.
- Apply the same behavior to a `required_message` containing a `${}` reference in a single-language form. The expanded XPath path must appear in an `<output value="..."/>` element in the generated message value.
- Surrounding whitespace within the `<output>` element's `value` attribute is not significant.
