SqliteConnector has no attribute host
### System Info

OS: Ubuntu
Python: 3.10
Same error on multiple pandasai versions from 2.07 to latest

### 🐛 Describe the bug

When I initialise an agent with a list of SqliteConnectors (one for each table of my db), and then proceed to chat with it, it throws an attribute error: SqliteConnector has no attribute host. I suspect there is an issue in the input validation.

### Additional contract requirements

- The reported failure happens during the agent's input validation, which is exercised when the agent is configured with `direct_sql=True`. Initialising an `Agent` with a list of `SqliteConnector` instances and calling `chat` must not raise the reported `host` `AttributeError`.
- `SqliteConnector.equals(other)` returns `True` only when `other` is a `SqliteConnector` whose configuration has the same `dialect`, `driver`, and `database` values; it returns `False` otherwise, including when any one of those values differs.
- The string representation of the value returned by `chat` must not contain `has no attribute 'host'`.
