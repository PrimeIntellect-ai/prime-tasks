[Bug] `#[derive(Template)]` panics when using `include` with nested templates
I've built a small test to reproduce the bug, which you can see [here](https://github.com/rinja-rs/rinja/compare/master...LukeMathWalker:rinja:includes).

What I think is happening:

- The base template includes the fragment using a path prefix with the folder that contains it (i.e. `included/`)
- The prefixed path is not valid when used from the leaf template, where the correct path prefix would be `../included/`
- The leaf template is resolving the includes in the base template as if the base template belonged to the same folder of the leaf template, which isn't the case

I don't have a fix (yet), but putting this up here for visibility in case others bump into it.
