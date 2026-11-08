Question: Filename appearing next to command in help menu
Just a quick question. I am not sure if this is a NodeJS issue or what, but when I run the example yargs code, I get the following in my terminal:

```
example.js <cmd> [args]

Commands:
  example.js hello [name]  welcome ter yargs!

Options:
  --version  Show version number                                       [boolean]
  --help     Show help                                                 [boolean]
```

In the example, the filename is not next to the command `hello` under the `Commands` section. Just wondering how to get the filename out of that section so that it looks like the one from the example:

```
  Commands:
    hello [name]  welcome ter yargs!

```

### Additional contract requirements

A Yargs instance must provide a chainable `.scriptName(name)` setting. Setting the name to the empty string must omit the executable filename from command entries in the help Commands section, while retaining each command's positional syntax and description.
