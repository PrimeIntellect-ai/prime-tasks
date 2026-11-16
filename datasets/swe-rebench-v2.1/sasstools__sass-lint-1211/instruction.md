sass-lint:disable-next-line
At the moment, you can do:

```sass
overflow-x: scroll !important; // sass-lint:disable-line no-important
```

Or:

```sass
// sass-lint:disable no-important
overflow-x: scroll !important;
// sass-lint:enable no-important
```

The first is not ideal when you want to add a reason/description and the line is already quite long, and the second is unnecessarily verbose.

TSLint supports a `tslint:disable-next-line` alternative, which would look like this:

```sass
// sass-lint:disable-next-line no-important -- The reason for this is because ...
overflow-x: scroll !important;
```

It would be nice to have this option.
