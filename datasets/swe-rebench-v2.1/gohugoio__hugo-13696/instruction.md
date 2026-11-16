Allow cascading of `outputs` front matter field to pages created by content adapters
The ability to set the `outputs` front matter field in pages created by a content adapter was added in https://github.com/gohugoio/hugo/issues/13689, but you cannot cascade values into these fields.

This is not a case of trying to cascade a value into a field that has already been set.

Test case to follow.

### Additional contract requirements

When a cascade provides `outputs`, that value must be applied to a page created by a content adapter if the page does not already define `outputs` itself.
