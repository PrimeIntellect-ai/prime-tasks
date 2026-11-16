Misleading error message when file has a syntax error
I have run into this twice where the overloaded `Code.ensure_compiled?` error is overloaded in Commanded and displays a canned message about missing aliases.

For example, I was missing an alias in this case for `AuditDenied` and `DenyAudit`, but the error makes you think something is wrong in the router, not in the aggregate.

```elixir
defmodule Capacitor.Aggregates.Audit do
  alias Capacitor.Aggregates.Audit
  alias Capacitor.Commands.{ApproveAudit, CreateAudit}
  alias Capacitor.Events.{AuditApproved, AuditCreated}

 # ...
  def execute(%Audit{status: :open}, %DenyAudit{} = command) do
    AuditDenied.new(command)
  end
end
```

Here is the error I received trying to run `mix compile`

<img width="829" alt="Screen Shot 2020-03-27 at 9 37 23 AM" src="https://user-images.githubusercontent.com/16150/77773343-178a9580-700f-11ea-9d29-d11477d95100.png">

This sends you to the `router.ex` to look for a missing alias only to find it's another file.

---

I had a similar issue yesterday but that time it was a typo in one of my Commands. The only way I was able to find it was to comment out chunks of code and find what made `mix compile` pass.

Is there any way to make this error more friendly to point to where the issue in fact is?

### Additional contract requirements

- For a failure involving `Commanded.Commands.UnknownCommand`, include the literal `UnknownCommand` in either the exception message or stderr output, and do not include `perhaps you forgot to `alias` the namespace` in the exception message.
