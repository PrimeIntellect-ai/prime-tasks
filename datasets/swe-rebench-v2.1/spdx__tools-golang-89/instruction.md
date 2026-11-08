tvsaver: missing text flags for various fields
In tvsaver, it appears that [HIDDEN]:

https://github.com/spdx/tools-golang/blob/8574b91809e949442fa0cbf3174d9ae83cd69f60/tvsaver/saver2v2/save_file.go#L53-L58

This means that if those fields contain multi-line text, the output will be invalid because they are missing the `<text></text>` wrapping tags.

* [x] Spot-check other Comments fields as well
* [x] [HIDDEN]

### Additional contract requirements

- In SPDX tag format versions 2.1 and 2.2, multiline `FileComment` and `FileNotice` values must be enclosed in `<text>` and `</text>` so the output is valid.
- Multiline values in other comment fields must likewise use the `<text>...</text>` wrapping required for valid SPDX tag output.
- In both SPDX tag format versions 2.1 and 2.2, multiline `PackageCopyrightText` values must also be enclosed in `<text>` and `</text>`.
