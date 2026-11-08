False positive on MultiAliasImportRequireUse when using multiple modules in same file
### Precheck

* Proposals for new features should be submitted via: https://github.com/rrrene/credo-proposals
* For bugs, please do a quick search and make sure the bug has not yet been reported here
   * I have not found any other issue about MultiAlias used in files with multiple modules

### Environment

* Credo version (`mix credo -v`): 1.6.7
* Erlang/Elixir version (`elixir -v`): 1.13.4-otp-25 and 1.12.3-otp-24
* Operating system: Ubuntu 22 and macOS Ventura

### What were you trying to do?

Example repository: https://github.com/ZeLarpMaster/CredoMultiAliasExample

TL;DR in a single file:

```elixir
defmodule CredoMultiAliasExample.Bar do
  @moduledoc "This module aliases another module"

  alias CredoMultiAliasExample.Foo
end

defmodule CredoMultiAliasExample.Baz do
  @moduledoc "This module aliases a different module under the same parent"

  alias CredoMultiAliasExample.Bar
end
```

Moving the 2nd `defmodule` into its own file fixes the issue even though that's effectively the same thing.

### Expected outcome

No issues found

### Actual outcome

>   Consistency
┃
┃ [C] ↗ Most of the time you are using the multi-alias/require/import/use syntax, but here you are using multiple single
┃       directives
┃       lib/credo_multi_alias_example.ex:16 #(CredoMultiAliasExample.Baz)
