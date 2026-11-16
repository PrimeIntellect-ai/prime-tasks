Display list of available formatters with help for --format
In GitLab by @blueyed on Apr 26, 2018, 03:32

`flake8 --help` contains:

> --format=format       Format errors according to the chosen formatter.

It would be nice/helpful if the list of available formats would be listed there.

### Additional contract requirements

- The `--format` help text must include `(default, pylint, quiet-filename, quiet-nothing)`.
