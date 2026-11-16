Null node found in short-form `if` body
In the following code (see also [AST Explorer snippet](https://astexplorer.net/#/gist/dcde248b9867b77c126e2e926dd06f43/4029a50b0d58062ef70097eb4208d89ab9680ca6)) the `if` statement's body is currently parsed as `{kind: "block", children: [null]}`.

```php
<?php if (true): ?>
<?php endif; ?>
```

I have a PR upcoming to fix and regression-test this.

### Additional contract requirements

- For an empty short-form `if` with an `else`, the `body` and `alternate` blocks must each have `children.length` exactly `0`.
