Enhancement(anta.tests): Hardware module tests should impose input restrictions on fields using field validators
Currently, some tests are accepting inputs as plain strings. We should implement field validation in these cases.

Example:
```
anta.tests.hardware:
      - VerifyEnvironmentPower:
          states:
            - ok
```


We have possible values for Fan status for example
`'failed', 'ok', 'unknownHwStatus' `

### Additional contract requirements

- The valid values for `VerifyEnvironmentCooling.states` are `failed`, `ok`, `unknownHwStatus`, `powerLoss`, and `unsupported`. The valid values for `VerifyEnvironmentPower.states` are `ok`, `unknown`, `powerLoss`, and `failed`.
