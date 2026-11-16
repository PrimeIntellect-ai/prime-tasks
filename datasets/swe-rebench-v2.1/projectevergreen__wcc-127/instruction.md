support `shadowrootmode` attribute for declarative shadow DOM
## Summary
The currently used attribute for marking a declarative shadow root on a `<template>` tag, `shadowroot` is / has been deprecated
- https://chromestatus.com/feature/6239658726391808
- https://chromiumdash.appspot.com/schedule

> The old `shadowroot` attribute is deprecated as of Chrome M112, and it will be removed (no longer supported) in Chrome M119, which goes to Stable on November 1, 2023.

![Screenshot 2023-12-26 at 4 14 27 PM](https://github.com/ProjectEvergreen/wcc/assets/895923/4f1def9b-5a9f-48e1-b7b2-3accd0dac14e)


## Details
The new `shadowrootmode` attribute should be used instead.
> The standards-track `shadowrootmode` attribute, which enables declarative Shadow DOM, was shipped in Chrome 111 [1]. The older, non-standard `shadowroot` attribute is now deprecated. During the deprecation period, both attributes are functional, however the `shadowroot` attribute does not enable the new streaming behavior, whereas `shadowrootmode` allows streaming of content. _**There is a straightforward migration path: [HIDDEN]**_.

Will probably just require some small updates to test cases, but should be a pretty straight forward [HIDDEN].

### Additional contract requirements

- WCC-rendered declarative shadow-root templates must use `shadowrootmode` rather than `shadowroot`, preserving the existing `open` mode.
