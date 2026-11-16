Falls on checking multi-line values
Example:

```env
MULTILINE="
{
    'key': 'value'
}
"
```

Result:

```
Checking .env
thread 'main' panicked at 'begin <= end (1 <= 0) when slicing `"`', src/common/line_entry.rs:94:26
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```
