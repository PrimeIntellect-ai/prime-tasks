Ignore interpolation for comments
Hi.

I've just been shuffling around some build instructions encapsulated in my justfiles. And commented out one such build instruction (since the build system of jax has been in flux).

```just
#cd jax-{{TAG}} && bazelisk run --verbose-failure=true //jaxlib/tools:build_wheel -- --output_path=dist --cpu=x86_64
```

just then told me the following:

```console
error: Variable `TAG` not defined
```

So, basically, it tried to interpolate the TAG value in the comment. I believe this is a situation where you should opt out of interpolation.

Of course, this depends whether or not the comment is a comment for the shell, or a comment for just. It seems to be a comment for the shell, in which case, well, I would understand just not being aware of what is a comment for the shell.

Nonetheless, the ergonomics of it seems suboptimal: I'd like to wildly refactor my build instructions without having just complaining about failing to interpolate my comments...

EDIT: It can be fixed by putting the # as the first element of the line and not putting it after the tab. But, still, it feels wrong.

### Additional contract requirements

- With `set ignore-comments`, comments are not analyzed for undefined variables, but interpolation syntax in comments must still be valid. For `# {{ foo bar }}`, report exactly:

```text
error: Expected '}}', '(', '+', or '/', but found identifier
 ——▶ justfile:4:12
  │
4 │   # {{ foo bar }}
  │            ^^^
```
