EBADF from fs.promises.readFile() and O_CREAT
Had a bunch of tests failing with EBADF even after updating to `^4.10` (as mentioned in #245), finally managed to track it down.

When trying to mock `fs.promises.readFile()` with the `fs.constants.O_CREAT` flag, an `EBADF` is raised if the file does not previously exist. If the file is created manually or the flag is not used, it reads normally or raises `ENOENT` as it should.

Reproducable:
```javascript
import mock from "mock-fs";
import { promises, constants } from "fs";

mock({ "foo.txt": "bar" });
const str1 = await promises.readFile("foo.txt"); // works fine
const str2 = await promises.readFile("bar.txt"); // ENOENT, as expected
const str3 = await promises.readFile("foo.txt", constants.O_CREAT | cosntants.O_RDONLY); // works
const str4 = await promises.readFile("bar.txt", constants.O_CREAT | constants.O_RDONLY); // EBADF, unexpected behavior.
```

node: `12.6.0`
mock-fs: `4.10.4`

### Additional contract requirements

When `fs.promises.readFile` is called for a nonexistent path with `O_CREAT | O_RDONLY`, it must create the file and resolve with empty contents rather than rejecting with `EBADF`. Accept the flag both as the numeric argument shown above and in the standard options object through its `flag` property.
