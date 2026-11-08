Dependency executed twice when order changes
Perhaps a bug, or I am the bug, but I cannot get `just` to handle dependency execution like it does in the docs. The docs state "Dependencies will always run first, even if they are passed after a recipe that depends on them" and then shows:
```$ just test build
cc main.c foo.c bar.c -o main
./test
testing… all tests passed!
```
In this case, `build` is only ran once.

If I replicate this, but with some simple `echo` commands, I get the dependency being executed twice:
```
build:
    echo "building something"

test: build
    echo "testing something"
```
```
$ just test build
echo "building something"
building something
echo "testing something"
testing something
echo "building something"
building something
```
To get the intended behavior, I have to call `build` before `test`:
```
$just build test
echo "building something"
building something
echo "testing something"
testing something
```

The end goal is to have multiple recipes have the same dependency but only execute said dependency once, irregardless of order. Since the docs seem to show it being possible, I am wondering if I am the bug?

### Additional contract requirements

- Requesting the same recipe more than once on the command line runs it only once.
- When a recipe is requested explicitly and is also a dependency of another requested recipe, it runs only once, regardless of the order in which the recipes are requested.
