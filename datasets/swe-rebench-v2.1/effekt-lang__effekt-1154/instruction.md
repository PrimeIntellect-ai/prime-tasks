Incorrectly applies tail resumption optimization under var scope
Effekt's optimizations are currently not semantics-preserving for the following program:

<details>

```scala
effect flip(): Bool

def all{prog: => Unit / {flip}} = {
  try {
    prog()
  } with flip {
    resume(true)
    resume(false)
  }
}

interface State[T] {
  def get(): T
  def set(x: T): Unit
}

interface allocate {
  def fresh[T, R](init: T){k: {State[T]} => R}: R
}

def newRegion[T]{prog: {r: allocate} => T}: T = {
  try {
    prog{r}
  } with r: allocate {
    def fresh[T, R](init) = {
      var x = init
      def s = new State[T] {
        def get() = x
        def set(y) = {
          x = y
        }
      }
      resume{{k} => k{s}}
    }
  }
}

def main() = {
  newRegion { {r} =>
    all {
      with def x = r.fresh(0)
      if (do flip()) {
        x.set(3)
      } else {
      }
      println(x.get())
    }
  }
}
```

</details >

with optimizations:

```console
> effekt regions.effekt
3
0
```

without optimizations:

```console
> effekt regions.effekt --no-optimize
3
3
```

### Additional contract requirements

- Add the supplied program as the regression example `examples/pos/issue1153.effekt`.
