Broadway.test_messages/2 doesn't send ack when using batchers
Here's a test that reproduces it:

```elixir
defmodule EmptyProducer do
  use GenStage
  @behaviour Broadway.Producer

  @impl true
  def init(_args) do
    {:producer, []}
  end

  @impl true
  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end
end

defmodule MyBroadway do
  use Broadway

  @impl true
  def handle_message(:default, message, _context) do
    message
  end
end

defmodule BugTest do
  use ExUnit.Case

  test "works", c do
    {:ok, pid} =
      Broadway.start_link(MyBroadway,
        name: c.test,
        producers: [
          default: [
            module: {EmptyProducer, []}
          ]
        ],
        processors: [
          default: [
            stages: 1
          ]
        ]
      )

    ref = Broadway.test_messages(pid, [1])
    assert_receive {:ack, ^ref, [%{data: 1}], []}
  end

  test "works with batchers", c do
    {:ok, pid} =
      Broadway.start_link(MyBroadway,
        name: c.test,
        producers: [
          default: [
            module: {EmptyProducer, []}
          ]
        ],
        batchers: [
          default: [
            stages: 1
          ]
        ],
        processors: [
          default: [
            stages: 1
          ]
        ]
      )

    ref = Broadway.test_messages(pid, [1])
    assert_receive {:ack, ^ref, [%{data: 1}], []}
  end
end
```

The 2nd test fails with:

```
  1) test works with batchers (BugTest)
     test/bug_test.exs:48
     No message matching {:ack, ^ref, [%{data: 1}], []} after 100ms.
     The following variables were pinned:
       ref = #Reference<0.1852397191.3371696133.32665>
     The process mailbox is empty.
     code: assert_receive {:ack, ^ref, [%{data: 1}], []}
     stacktrace:
       test/bug_test.exs:70: (test)
```
