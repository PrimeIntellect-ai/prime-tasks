Generate tests from `flow generate contract`
`flow generate contract` should automatically generate boilerplated test files to help developers test their code.  A flag could be added (`--skip-tests`) to avoid this feature if it is unwanted.

This fits in with https://github.com/onflow/flow-cli/issues/1390 -> the tests could live in `cadence/tests`

### Additional contract requirements

When `flow generate contract <name>` generates a contract, it must also generate a boilerplate Cadence test file for that contract:

- The test file is written to `cadence/tests/<name>_test.cdc`, where `<name>` is the contract name with any trailing `.cdc` extension removed (for example, `flow generate contract Tester.cdc` writes `cadence/tests/Tester_test.cdc`).
- The generated file should provide a starter test that exercises the generated contract and verifies that it can be deployed successfully.
