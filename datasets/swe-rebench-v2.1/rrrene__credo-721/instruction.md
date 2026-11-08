Proposal: warn on Mix.env usage in runtime files
Hi, I hope this proposal makes sense, I'm relatively new to Elixir!

### Environment

* Credo version (`mix credo -v`): 1.1.4
* Erlang/Elixir version (`elixir -v`): Elixir 1.7.4 (compiled with Erlang/OTP 21)
* Operating system: Ubuntu Linux

### What were you trying to do?

My program failed upon deployment because `Mix.env` was called inside runtime code. This works fine in dev and test environments because Mix is available, as well as in the config during build. So it can cause unexpected failures if Mix is unavailable in production as [recommend](https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html#environments). It seems like Credo would be a good place to catch such a mistake?

### Expected outcome

Credo emits a warning that `Mix.env` is being used in code where it won't be available at runtime.

### Actual outcome

Credo is silent on the issue.

### Additional contract requirements

- The check is provided by the module `Credo.Check.Warning.MixEnv`, which exposes `run(source_file, params \\ [])`. `source_file` is a `%Credo.SourceFile{}` and `params` is a keyword list of options. It returns a list of `%Credo.Issue{}` structs.
- Every call to `Mix.env/0` in the analyzed source file is reported, including the capture form `&Mix.env/0`. A source file that contains no such call produces no issues.
- Calls in files whose filename has the `.exs` extension are not reported.
- The check accepts an `:excluded_paths` option: a list of strings or regular expressions. A file is excluded when its directory path matches one of the entries; a string entry matches when the file's directory path starts with that string, and a regular expression entry matches when it matches the file's directory path. Calls in excluded files are not reported.
- Each reported issue carries the message `There should be no calls to Mix.env in application code.`
