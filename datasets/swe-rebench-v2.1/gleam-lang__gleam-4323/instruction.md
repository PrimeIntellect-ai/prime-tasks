`echo` throws error when used at start of pipeline
When you have an `echo` as the first term of a pipeline, the compiler returns a rather cryptic error

Gleam: 1.9.0
OS: Ubuntu 22.04.5 LTS
Runtime: Erlang

Logs (filtered for the error part):
```
{compiling,"/home/pedrohcf/dev/chess_bot/build/dev/erlang/chess_bot/_gleam_artefacts/tests.erl"}
src/tests.gleam:4:5: function echo/4 undefined
%    4| }
%     |  ^^^^

src/tests.gleam:5:14: variable '_pipe' is unbound
src/tests.gleam:4:10: Warning: variable '_pipe' is bound multiple times in this pattern.
If you mean to ignore this value, use '_' or
a different underscore-prefixed name
%    4| }
%     |  ^^^^^^^^^

{failed,"/home/pedrohcf/dev/chess_bot/build/dev/erlang/chess_bot/_gleam_artefacts/tests.erl"}
{compiled,chess_bot,
          "/home/pedrohcf/dev/chess_bot/build/dev/erlang/chess_bot/ebin/chess_bot.beam"}
ERROR Failed error=ShellCommand { program: "escript", reason: Unknown }
error: Shell command failure

There was a problem when running the shell command `escript`.
```

### Additional contract requirements

- The Erlang code generated for a program that uses `echo` as the first term of a
  pipeline must be valid Erlang that compiles without errors.
