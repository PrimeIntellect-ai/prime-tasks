Nested segments
As far I see in the code, there is no support for nested segments for Transactions. Example:
```
defmodule MyMod do
  use NewRelic.Tracer

@trace :outer
def outer() do
  :timer.sleep(1000)
  inner()
end

@trace :inner
def inner() do
  :timer.sleep(1000)
  :ok
  end
end
```

The segments will be sent to NewRelic in flat namespace, i.e there will be no indication that the `inner` function is nested in `outer` part. It may lead to confusing data displayed in the `Transaction traces` in the `Trace details` tab.


Most likely I will develop this feature in the `elixir-agent` plugin for our purposes (and maybe create PR here later on). Hence my question is:
Where can I find the documentation of REST API of the NewRelic?
I mean the API that the plugin uses for pushing transactions, segments and spans.
I believe there is a support for nested segments in NewRelic in general, so how would look like http  request ?

### Additional contract requirements

- When a traced function calls another traced function during the same transaction, the transaction trace should represent the inner function's segment as nested under the outer function's segment, rather than as a flat peer.
