Parse error using @inbounds inside an expression
The following is properly formatted by `JuliaFormatter`:

```
threads_count = @inbounds min(remaining_batches_count, threads_count_of_processes[worker_id])
```

But the following fails with a parse error:

```
threads_count = min(remaining_batches_count, @inbounds threads_count_of_processes[worker_id])
```

BTW, it would be nice if, when there is a parse error, there was some indication of where the error was in the file... I had to do a binary search to isolate this line.

### Additional contract requirements

- For the input `var = call(a, @macrocall b)`, the formatter must produce exactly:

```
var =
    call(
        a,
        @macrocall b
    )
```
- For the input `threads_count = min(remaining_batches_count, @inbounds threads_count_of_processes[worker_id])`, the formatter must produce exactly:

```
threads_count =
    min(
        remaining_batches_count,
        @inbounds threads_count_of_processes[worker_id]
    )
```
