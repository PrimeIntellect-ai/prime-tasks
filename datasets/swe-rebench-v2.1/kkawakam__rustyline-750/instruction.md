CompletionType::List does not support completion candidates that are shorter than the input
Thank you for maintaining this crate — we use it in [Numbat](https://github.com/sharkdp/numbat) and it works great.

We want to implement a feature where a user could type something like `\hbar` in the REPL, press <kbd>Tab</kbd> and it would be replaced by `ℏ`. This seems to work fine when using `CompletionType::Circular`, but it does not work for `CompletionType::List`. Words will only be replaced if they are longer than the input. This is probably due to this check:

[HIDDEN]

Would it be possible to support this use case?

Remark: that check above should probably use [HIDDEN] (?).

### Additional contract requirements

- In `CompletionType::List` mode, pressing Tab with a single completion candidate shorter than the typed input must replace the input with that candidate. This includes replacing `\hbar` with `ℏ`.
