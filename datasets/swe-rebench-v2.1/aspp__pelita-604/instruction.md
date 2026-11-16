--timeout setting is ignored in RemoteTeam
We need to add (or rather: reenable) proper handling of timeouts in RemoteTeam. Also, each timeout now creates two errors. The timeout itself and an illegal move error.

### Additional contract requirements

- When a player exceeds the per-move `timeout_length`, the game records a `PlayerTimeout` error for that team in the `'errors'` state entry.
- Each `PlayerTimeout` error entry has `'description': ''`.
- An illegal move is recorded as an error entry with `'reason': 'illegal move'` and the attempted `'bot_position'`.
