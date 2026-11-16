Improve cyclic dependency detection output
The "cyclic dependency detected!" output right now is very verbose, which makes it hard to determine where the cycle is. We should trim down the output so that it only includes projects that are in the cycle.

### Additional contract requirements

- The cycle error message identifies each participating project by its Clojure printed representation (`pr-str`); for example the keyword `:a` is shown as `:a`.
