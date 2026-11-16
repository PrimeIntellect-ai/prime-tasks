Nomalize 'To update, run' advice
Currently when you regenerate a requirements.txt, if you run with syntactically different, but semantically identical command line flags the 'To update, run' advice changes.

The 'To update, run' advice should be normalized by:

* expanding short to long,
* removing values that are already default,
* sorting the arguments
* removing arguments that don't change build behaviour like 'verbose'

### Additional contract requirements

- The "To update, run:" advice in the header of a generated file is a single command line that starts with `pip-compile`. Values containing spaces or shell-special characters are quoted so the line can be pasted into a shell.
- Semantically identical invocations produce identical advice, regardless of the order of their arguments or of whether an option is written in its short or long form (for example `-p` and `--pre`, or `-i URL` and `--index-url=URL`).
- Short options are shown in their long form.
- Options whose values are already the default are omitted from the advice; a value that differs from the default is kept.
- The arguments in the advice are sorted alphabetically, and the source files are sorted as well.
- Arguments that do not change the build are omitted from the advice, such as verbosity (`-v`, `-q`) and dry-run. One-off options such as `--upgrade` and `--rebuild` are omitted too.
- The output writer accepts the Click context of the `pip-compile` invocation as its `click_ctx` argument.
