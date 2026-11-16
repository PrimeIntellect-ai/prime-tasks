Sort pre/post scripts with colon together
I often use `pre` and `post` scripts such as `prebuild`, `build` and `postbuild`. Sometimes I split them into multiple scripts such as `prebuild:foo` and `prebuild:bar` with `prebuild` running something like [npm-run-all](https://www.npmjs.com/package/npm-run-all2) `run-s`.

The `prebuild` and `postbuild` is neatly sorted as expected:

```json
{
  "scripts": {
    "prebuild": "..",
    "build": "..",
    "postbuild": ".."
  }
}
```

However when using `:` the sorting isn't as neat any longer, a longer example of this is:

```json
{
  "scripts": {
    "prebuild": "run-s prebuild:*",
    "build": "run-s build:*",
    "postbuild": "run-s prebuild:*",
    "build:bar": "node bar.js",
    "build:baz": "node baz.js",
    "build:foo": "node foo.js",
    "d-unrelated": "..",
    "e-unrelated": "..",
    "f-unrelated": "..",
    "postbuild:1": "node prebuild.js 1",
    "postbuild:2": "node prebuild.js 2",
    "postbuild:3": "node prebuild.js 3",
    "prebuild:1": "node prebuild.js 1",
    "prebuild:2": "node prebuild.js 2",
    "prebuild:3": "node prebuild.js 3"
  }
}
```

The expected order would be:

```json
{
  "name": "scripts-with-colon",
  "version": "1.2.3",
  "scripts": {
    "prebuild": "run-s prebuild:*",
    "prebuild:1": "node prebuild.js 1",
    "prebuild:2": "node prebuild.js 2",
    "prebuild:3": "node prebuild.js 3",
    "build": "run-s build:*",
    "build:bar": "node bar.js",
    "build:baz": "node baz.js",
    "build:foo": "node foo.js",
    "postbuild": "run-s prebuild:*",
    "postbuild:1": "node prebuild.js 1",
    "postbuild:2": "node prebuild.js 2",
    "postbuild:3": "node prebuild.js 3",
    "d-unrelated": "..",
    "e-unrelated": "..",
    "f-unrelated": "..",
  }
}
```

If you think this is reasonable I could try to create a PR to implement this change.
