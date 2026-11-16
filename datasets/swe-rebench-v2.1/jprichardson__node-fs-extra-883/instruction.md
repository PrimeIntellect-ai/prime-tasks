copy filter called twice
<!-- First ensure you installed the latest version of fs-extra -->
<!-- If your bug still exists please fill out the following information if it applies to your issue: -->
<!-- Please check if you have installed a supported version of Node.js as written in "engines" in the package.json -->
- **Operating System:** MacOS 10.14.6
- **Node.js version:** 14.1.0
- **`fs-extra` version:** 9.0.1

Hi,

Copy filter function called twice for same source and destination. I found a similar report for `emptyDir`, but couldn't see a case for `copy`.

Is this expected for some reason?

Example:

```js
// Below code outputs: 1 2, whereas I expected only 1.
const { copy } = require("fs-extra");

let i = 1;

copy("README.md", "README2.md", {
  filter: () => {
    console.log(i++);
    return true;
  },
});
```

### Additional contract requirements

- For an item accepted by its filter, asynchronous `copy` invokes the filter once for that source/destination pair. This applies to the root item and entries within copied directories.
