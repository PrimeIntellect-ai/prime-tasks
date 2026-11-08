Refer to a String that can be set to a flag from a variable
Thanks for the useful library :)

Now, I wrote `@Spyable(behindPreprocessorFlag: "DEBUG")` in a lot of code.
So I felt I would like to set "DEBUG" as a variable.

<img width="354" alt="Screenshot 2024-02-02 at 12 29 36" src="https://github.com/Matejkob/swift-spyable/assets/24838521/42687902-ccff-4ae5-ad15-d4fd7fcfe204">

In this case `if DEBUG` is not generated.
Are there any good way?

### Additional contract requirements

- The `@Spyable` attribute accepts a `behindPreprocessorFlag` argument whose value must be a static string literal. When it is a static string literal, the generated spy peer is wrapped in a conditional-compilation block for that flag, for example `#if DEBUG` ... `#endif`.
- A `behindPreprocessorFlag` value that is not a static string literal, such as a reference to a variable or a string containing interpolation, is invalid.
- For an invalid `behindPreprocessorFlag` argument, emit the diagnostic message "The `behindPreprocessorFlag` argument requires a static string literal" at the `@Spyable` attribute location, and emit the note message "Provide a literal string value without any dynamic expressions or interpolations to meet the static string literal requirement." at the start of the argument expression.
- When the `behindPreprocessorFlag` argument is invalid, the spy peer is still generated, without a conditional-compilation wrapper.
