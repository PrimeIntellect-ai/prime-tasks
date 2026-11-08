Deprecate the old 'pyomo' command syntax
In earlier releases, we supported commands like
`  pyomo --solver=glpk foo.py bar.dat`
And we moved to a nested pyomo command, which uses the following syntax:
`  pyomo solve --solver=glpk foo.py bar.dat`

However, to enable graceful transition for users, we added a hack to transition to the old syntax if it looks like the user is not specifying a valid subcommand.  However, this leads to confusing error messages, and I think it's time to deprecate that hack and start throwing warnings that this hack will be removed in an upcoming release.

### Additional contract requirements

- The warning message must include the exact text `Running the 'pyomo' script with no subcommand`.
- The command-line entry point is the public function `main(args=None)` in the module `pyomo.scripting.pyomo_main`.
- When `args` is `None`, `main` uses `sys.argv[1:]` as the argument list.
- When no subcommand is given, `main` defaults to the `solve` subcommand.
- `main` terminates the interpreter by raising `SystemExit`.
