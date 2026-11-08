Strange docs for `_` function arguments
When a function has an argument that is ignored like this: `fn absurd(_: Void) -> a` the generated documentation will look like this:

![Image](https://github.com/user-attachments/assets/ef824aa3-7054-4871-b546-738da04f9955)

With no name before the type annotation. I would change the doc generation so that there's always something  before the type.

### Additional contract requirements

When a function argument is ignored, the generated documentation shows the name `arg` before the argument's type.
