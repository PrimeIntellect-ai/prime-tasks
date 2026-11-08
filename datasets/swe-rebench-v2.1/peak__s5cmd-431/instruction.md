s5cmd ls --recursive ... prints error text to stdout
I am converting a workflow from s3cmd to s5cmd, and didn't notice that s5cmd doesn't support recursive.  I had redirected the `ls` to a file(for later processing with shell tools), and the script was failing(via set -e).  I would have expected an error to be printed to stderr, like any other tool, so I was initially confused.

If s5cmd detects an error with cmdline arguments, it should print the help text to stderr, not stdout.

### Additional contract requirements

- For the invocation `s5cmd --recursive ls`, stderr must include these lines in order: `Incorrect Usage: flag provided but not defined: -recursive` and `See 's5cmd --help' for usage`.
