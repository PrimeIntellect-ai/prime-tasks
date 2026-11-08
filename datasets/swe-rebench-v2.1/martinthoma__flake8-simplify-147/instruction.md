yield from is not allowed in async function
## Desired change
Do not warning if a SIM104 is encountered inside an async function or method.

* **Rule(s)**: SIM104
* **Adjustment**: In which way should it/they be adjusted?
Do not warning if a SIM104 is encountered inside an async function or method.

## Explanation

Why is the adjustment necessary / better?

The suggested fix to replace a for yield loop with a `yield from` statement is [invalid](https://peps.python.org/pep-0525/#asynchronous-yield-from) inside an async function.

## Example

This is an example where the mentioned rule(s) would currently be suboptimal:

```python
async fib(limit=10):
    if limit == 1:
        yield 0
    if limit == 2:
        yield 0
        yield 1
    i, j = 0, 1
    for _ in range(2, limit):
        n = i + j
        yield n
        i, j = j, n
```
