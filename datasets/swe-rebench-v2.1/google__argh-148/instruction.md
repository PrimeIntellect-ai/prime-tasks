Allow positional arguments to be omitted from the help text
I have been using argh to develop a new cargo command. Cargo passes the actual command being executed as the first command line argument. In order to capture (and ignore) that argument, I have an extra positional argument in the structure, followed by the *real* positional arguments. However, this first argument shows up in the command line help and is quite confusing as users should not actually enter it. It would be good to have a flag that omits a positional argument (and possibly others) from the generated help text.

### Additional contract requirements

The flag that omits an argument from the generated help text is the field attribute `hidden_help`. It is written together with the argument kind, for example `#[argh(positional, hidden_help)]`, and the annotated positional argument is left out of the generated help text (both the usage line and the positional arguments section).

A positional argument marked `hidden_help` remains part of normal positional parsing and receives its corresponding command-line value.
