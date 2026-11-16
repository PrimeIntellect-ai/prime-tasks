Incorrect search_path in example
As mentioned in https://github.com/enthought/pyface/issues/830#issuecomment-738954788 and the subsequent comments on that issue, the search_path in `Image_editor_demo` refers to a non existent path in traits.  This leads to the image never being able to be located, and without https://github.com/enthought/pyface/pull/831 actually, causes the corresponding intergration test to fail on the latest pyface.

The path should be updated to: [HIDDEN], and note to do this, [HIDDEN].

### Additional contract requirements

- The `Image_editor_demo` example's `search_path` must identify the existing `Extras` directory containing its image assets, so the demo can locate the image.
