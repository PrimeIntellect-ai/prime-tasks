EBADF reading directory with readFileSync()
The attached mocha test will fail with `Error: EBADF: bad file descriptor, read`.

While searching the issues I noticed some relating to graceful-fs - while it's technically in my node_modules dependency tree, I don't believe it's loaded during the test. I think it's only used for the vscode eslint extension.

This is on macOS 10.15.2, Node 12.14.0, mock-fs 4.10.4.

```
const assert = require('assert'),
  fs = require('fs'),
  mockFS = require('mock-fs');

describe('Test Suite', () => {
  before(() => {
    mockFS({
      root: {}
    });
  });

  after(() => {
    mockFS.restore();
  });

  it('should mock the file system', () => {
    let foo = fs.readFileSync('root');
  });
});
```

### Additional contract requirements

- Reading a directory as a file must fail with an error whose `code` is `EISDIR`, not `EBADF`. This applies to `fs.readFile`, `fs.readFileSync`, and `fs.promises.readFile`.
