Include custom metadata during command dispatch
The supported event stores provide storing metadata per event appended to a stream. It would be useful to allow this metadata to be provided during commanded dispatch.

An example usage would be to include the identity of the user invoking the command:

```elixir
command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}
metadata = %{"user_id" => "user-12345"}

:ok = BankRouter.dispatch(command, metadata: metdata)
```

The *optional* metadata would be recorded against any persisted events.
