ExperimentalWarning: The fs.promises API is experimental (Node.js 10.1.0)
<!-- Please fill out the following information if it applies to your issue: -->
- **Operating System:** MacOS 10.13.4
- **Node.js version:** 10.1.0
- **`fs-extra` version:** 5.0.0

Hello! First of all, thank you for the great work on maintaining fs-extra 🙇

With Node.js 10.1.0 recently released, we started to see the following warning in our test suite:

```
(node:7885) ExperimentalWarning: The fs.promises API is experimental
```

It turns out the `fs` module provides a new property `promises` which triggers the warning on the first access.

You can try it out yourself:

```
$ node -v
v10.1.0
$ node -e "console.log(typeof fs.promises)"
object
(node:8277) ExperimentalWarning: The fs.promises API is experimental
```

On Node.js version 10.0.0:

```
$ node -e "console.log(typeof fs.promises)"
undefined
```

Can we fix [lib/fs/index.js](https://github.com/jprichardson/node-fs-extra/blob/7d36349abe257c15ac1b216a374de697161ba5f3/lib/fs/index.js) to not emit ExperimentalWarning until the experimental API is actually accessed?
