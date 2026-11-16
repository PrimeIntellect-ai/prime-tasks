Item's `ext` interface should include the scientific extension
It's [allowed](https://github.com/stac-extensions/scientific?tab=readme-ov-file#scientific-citation-extension-specification) but it's not [there](https://github.com/stac-utils/pystac/blob/14a36942d395de47ebdb7f22477ce00c5a87348f/pystac/extensions/ext.py#L126-L197).

### Additional contract requirements

- The Item `ext` interface must expose the scientific extension as `item.ext.sci`. When the scientific extension is present on the Item, accessing this attribute returns its `ScientificExtension` bound to that Item; if it is not present, accessing it raises `ExtensionNotImplemented`.
