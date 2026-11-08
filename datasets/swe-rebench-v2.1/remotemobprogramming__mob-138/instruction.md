Add better message when issuing a mob command outside a git repository

### Additional contract requirements

When a mob command is run from a directory that is not inside a Git repository, mob must print the message:

    mob expects the current working directory to be a git repository.
