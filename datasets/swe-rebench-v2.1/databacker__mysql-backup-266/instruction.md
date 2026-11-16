Go version: Mutually exclusive flags check not working
## Expected Behavior
Supplying just the `--cron` flag or just the `--once` flag should work.

## Current Behavior
mysql-backup exits with errors depending on the flag

`ERRO[0000] error creating timer: option 'Cron' is exclusive and must not be used with Begin, Once or Frequency`

`ERRO[0000] error creating timer: option 'Once' is exclusive and must not be used with Begin, Cron or Frequency`


## Steps to Reproduce
on master branch:
`./mysql-backup dump --target /backup --cron "0 0 * * *"`
`./mysql-backup dump --target /backup --once`

via docker:
`docker run -e DB_DUMP_TARGET=/backup -e DB_DUMP_CRON="0 0 * * *" databack/mysql-backup:1.0.0-rc2 dump`
`docker run -e DB_DUMP_TARGET=/backup -e DB_DUMP_ONCE=true databack/mysql-backup:1.0.0-rc2 dump`

## Possible Solution
The `--begin`and `--frequency` flags have defaults (`+0` and `1440`) which are loaded at the time when mutually exclusive flags are checked. [HIDDEN]

## Possible Implementation
[HIDDEN]
```go
	[HIDDEN]
	[HIDDEN]
	[HIDDEN]
	[HIDDEN]
	[HIDDEN]
```
[HIDDEN]
```go
	// validate we do not have conflicting options
	[HIDDEN]
		return nil, errors.New("option 'Once' is exclusive and must not be used with Begin, Cron or Frequency")
	}

	[HIDDEN]
		return nil, errors.New("option 'Cron' is exclusive and must not be used with Begin, Once or Frequency")
	}
```

### Additional contract requirements

- Supplying `--cron` by itself or `--once` by itself must succeed; default values for `--begin` and `--frequency` must not make either invocation fail.
- The dump command must reject explicitly combining `--once` with `--cron`, `--begin`, or `--frequency`, and explicitly combining `--cron` with `--begin` or `--frequency`.
