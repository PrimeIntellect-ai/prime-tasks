Can't access env vars defined in Justfile from submodule
It seems that version 1.42 introduced a change https://github.com/casey/just/pull/2810 that does not allow submodules to access env variables defined in the main Justfile.

`Justfile`
```
mod test './test.justfile'

export a := "a"
```

`test.justfile`
```
test:
    echo $a
```

Running `just test` fails because a is unbound variable.
