Option to indent the closing bracket of a multiline element by +1
## Request / Idea
Thanks for the plugin. We are migrating a sizeable codebase to use it. One currently impossible style opinion would be really helpful for us: indenting the trailing `)` of a multiline element to the same indent level as the props.

## Input

```pug
ExampleComponent(
  variant="danger"
  title="Oh no, a connection error!"
)
```

## Expected Output

```pug
ExampleComponent(
  variant="danger"
  title="Oh no, a connection error!"
  )
```

## Crude Implementation

[HIDDEN]

## Additional Context

We feel this is preferable over the current default indent position as it allows you to both comment out the whole component one one go...

```pug
// Errors
// ExampleComponent(
  variant="danger"
  title="Oh no, a connection error!"
)
```

```pug
// Works
// ExampleComponent(
  variant="danger"
  title="Oh no, a connection error!"
  )
```

...as well as retains the ability to re-order the props easily without having to manually move the closing bracket to the end of the last prop.

Could this style be supported as an option? The code is trivial, so it's more of a bike-shedding question.

### Additional contract requirements

Expose this preference as the `pugClosingBracketIndentDepth` formatting option. It accepts numeric values `0` and `1`. When `pugBracketSameLine` is false, `0` preserves the current closing-parenthesis alignment and is the default when the option is omitted; `1` indents the closing parenthesis of a multiline element to the same indentation level as its attributes.
