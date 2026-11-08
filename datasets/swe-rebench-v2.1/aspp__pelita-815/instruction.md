Add team name in CI table
Remote players only show their team names making comparisons harder.

Conversely, the remote player should/could also include the spec name.

### Additional contract requirements

- The CI results table printed by the CI engine must show each player's team name alongside the player.
- Add a public method `add_team_name(self, name, team_name)` to the `DB_Wrapper` class in `contrib/ci_engine.py`. It stores a new entry, or updates an existing entry, mapping the player `name` to `team_name`. It returns nothing.
- Add a public method `get_team_name(self, p_name)` to the `DB_Wrapper` class in `contrib/ci_engine.py`. It returns the stored team name for the player `p_name` as a string, and raises `ValueError` if the player has no stored team name.
