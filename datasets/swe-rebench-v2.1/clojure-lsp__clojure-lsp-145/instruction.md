Support `doto`
clojure-lsp doesn't appear to be knowledgeable about `doto`, which inserts its first argument as the first argument to all subsequent forms:

![2020-04-14-184449_1207x272_scrot](https://user-images.githubusercontent.com/4909079/79281125-2632d280-7e80-11ea-8095-9b8654abe58a.png)

(The relevant functions above all have arities that are 1 greater than the number clojure-lsp is complaining about, so when `session` gets added in by `doto`, the number of arguments is correct.)

### Additional contract requirements

- Wrong-arity diagnostic messages must use the format `No overload for '<name>' with <count> argument` when the count is 1, and `No overload for '<name>' with <count> arguments` otherwise.
