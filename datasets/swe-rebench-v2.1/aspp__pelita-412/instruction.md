pytest warns about our TestPlayer
    WC1 /tmp/group1/test/test_drunk_player.py cannot collect test class 'TestPlayer' because it has a __init__ constructor

Maybe rename it?

### Additional contract requirements

- The player class formerly named `TestPlayer` is renamed to `SteppingPlayer`; `SteppingPlayer` is importable from `pelita.player`.
- `SteppingPlayer` is a subclass of `AbstractPlayer` and can be supplied to `SimpleTeam` and `GameMaster`.
- `SteppingPlayer(moves)` accepts a list or tuple of moves (direction tuples such as `east` and `west`) or a string of direction symbols (`^` north, `v` south, `<` west, `>` east, `-` stop), and returns the supplied moves in sequence, one per turn.
- `SteppingPlayer` raises `ValueError` when it is asked for a move after the supplied moves have been exhausted.
- The name `TestPlayer` is no longer available from `pelita.player`.
