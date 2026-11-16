Unhandled bounds
While testing filling forms I noticed a few cases where the text had really small font size.
It turned out that the issue was a negative bound, which apparently is valid.
[HIDDEN]
https://github.com/Hopding/pdf-lib/blob/581d87e2a12628df94161df72c9d36e661eb7e2c/src/api/text/layout.ts#L50

### Additional contract requirements

- A text form field whose widget has a negative height must be laid out the same way as the same field with the positive height (the same automatically chosen font size for the same text and width), rather than being shrunk to the minimum size.
