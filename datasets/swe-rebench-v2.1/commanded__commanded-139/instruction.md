Replace aggregate lifespan `after_command/1` callback with `after_event/1`
An aggregate process lifespan should be controlled by the domain events it creates, not the commands, since a command may be rejected or ignored.

The events created by an aggregate are returned when executing a command so it should be straightforward to call an `after_event/1` callback and pass it the last domain event.

### Additional contract requirements

The `Commanded.Aggregates.AggregateLifespan` behaviour defines a callback `after_event(event)` that receives the last domain event emitted by a command. It returns one of:

- a non-negative integer, specifying an inactivity timeout in milliseconds;
- `:infinity`, to prevent the aggregate instance from shutting down;
- `:stop`, to immediately shut down the aggregate process.

When `after_event/1` returns `:stop`, the aggregate process terminates with exit reason `:normal`.

When a command produces no events, the aggregate is not shut down.

`Commanded.Commands.Router` validates command registrations at compile time and raises an `ArgumentError` with these exact messages:

- when the same command is already registered in the router: "Command `Commanded.ExampleDomain.BankAccount.Commands.OpenAccount` has already been registered in router `DuplicateRouter`";
- when the command handler module does not define a `handle/2` function: "Command handler `InvalidHandler` does not define a `handle/2` function";
- when a configured aggregate lifespan module does not define an `after_event/1` function: "Aggregate lifespan `BankAccountLifespan` does not define a callback function: `after_event/1`".
