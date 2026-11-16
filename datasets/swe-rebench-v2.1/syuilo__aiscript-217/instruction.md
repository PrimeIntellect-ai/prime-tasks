for文で初期値に対して処理が実行されない

### Additional contract requirements

The `for` loop form `for (let i = start, count) { ... }` executes its body `count` times. The iterator variable `i` takes the values `start`, `start + 1`, ..., `start + count - 1`, so the initial value `start` is processed by the body. When the initial value is omitted (`for (let i, count)`), `start` defaults to `0`. The second argument is the number of iterations, not an inclusive upper bound.
