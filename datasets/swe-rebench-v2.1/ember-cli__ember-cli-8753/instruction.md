Formatting empty string arguments (and other things that requires shell escape)
The `--help` for a command like this...

```js
module.exports = {
  description: 'Generates a thing.',

  availableOptions: [
    {
      name: 'something',
      type: ['', 'foo', 'bar'], // setting to empty string is allowed
      default: '',
      aliases: [{ 'no-something': '' }],
    }
  ],

  // ...
};
```

Looks like...

```
        Generates a thing.
        --something (, foo, bar) (Default: )
          aliases: --no-something (--something=)
```

This is a bit hard to read. I suggest that we do this:

```
        Generates a thing.
        --something ("", foo, bar) (Default: "")
          aliases: --no-something (--something="")
```

Technically, this problem applies for other special characters that needs escaping too... but empty string is probably much more common so that would be a start. `ember generate component --help` has this problem today (`--path=`), but we are about this introduce more instances of this problem with [RFC #481](https://emberjs.github.io/rfcs/0481-component-templates-co-location.html#generator).
