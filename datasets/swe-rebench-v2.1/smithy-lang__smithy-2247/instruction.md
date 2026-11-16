How to detect duplicate shape definitions?
Hi!

I would like to detect and prevent duplicate definitions of shapes within a codebase. Does smithy-model allow me to do that?

At the moment, it appears that duplicate definitions are only logged as a warning, and there's nothing in the model loading result that would tell me that this happened. The SourceLocation also gets deduplicated into a single definition.

To reiterate/rephrase, I want to stop people from doing

```smithy

@length(min: 1)
string NonEmptyString

@length(min: 1)
string NonEmptyString

```

in my repository. This has happened before (presumably as a result of a mishandled merge conflict) and it's only producing noise.

### Additional contract requirements

- For duplicate equivalent definitions of `foo.baz#Foo`, the model-loading diagnostics must include the following formatted line exactly: `[NOTE] foo.baz#Foo: Ignoring duplicate but equivalent shape definition: foo.baz#Foo defined at | Model.IgnoredDuplicateDefinition`.
