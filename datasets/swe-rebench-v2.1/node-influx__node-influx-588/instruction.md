Placeholders / bind parameters should support number variables
## Expected Behavior

Placeholders / bind parameters should both number and string variables.

## Actual Behavior

Placeholders / bind parameters support only string variables

## Steps/Code to Reproduce the Problem

```
influx.query(
  'select * from response_times where host = $host and time > $from',
  {
    placeholders: { host: 'example', from: 1609459200000000000 }
  }
);
```

## Specifications

- Version: 5.9.1
- Platform: macOS

### Additional contract requirements

- `InfluxDB.query(statements: string | string[], options?: IQueryOptions)` is a public method of the `InfluxDB` class exported from the package's main module (`src/index.ts`).
- The optional `placeholders` option of `IQueryOptions` must support bind parameter values that are either strings or numbers.
