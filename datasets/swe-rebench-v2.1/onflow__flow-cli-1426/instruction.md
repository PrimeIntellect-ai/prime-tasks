Emulator command for migrating contracts/state to Cadence 1.0

### Issue To Be Solved

The CLI should have a command to take in an Emulator snapshot created using a recent Emulator version with Cadence v0.42, run the Cadence 1.0 contract and state migrations on it, and produce a new Emulator snapshot for the latest version  of the Emulator with Cadence v1.0.

### Suggest A Solution

- Add a command like `flow migrate`
- Call the Emulator's Cadence 1.0 migration function, added in https://github.com/onflow/flow-emulator/pull/557

### Additional contract requirements

- The migration command is exposed as the `state` subcommand of the `migrate` command, i.e. `flow migrate state`.
- The `state` command accepts a `--db-path` flag naming the SQLite database file (the Emulator snapshot) to migrate.
- Add a function `resolveStagedContracts(state *flowkit.State, contractNames []string) ([]migrations.StagedContract, error)` in package `migrate` (module path `github.com/onflow/flow-cli/internal/migrate`). For each requested contract name, return a staged contract containing its Emulator address and source, preserving the requested order.
- Add a function `migrateState(args []string, globalFlags command.GlobalFlags, logger output.Logger, flow flowkit.Services, state *flowkit.State) (command.Result, error)` in package `migrate` that runs the Cadence 1.0 contract and state migrations on the Emulator snapshot at the path given by the `--db-path` flag and writes the migrated snapshot back to that path.
