Removed hard-coded "kn" in usage/error messages
Instead use `argv[0]`, the first argument provided on the command line. If the command is called with a path, that path should be stripped off from the given argument.

See https://github.com/knative/client/pull/1175 for more context.
