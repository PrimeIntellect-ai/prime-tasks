[ENH] - Add support for .doc / .docx
### Feature description

Word documents are everywhere in the corporate world. We should support them out of the box. There are multiple Python packages out there that provide this functionality. We should do a light comparison of them to get a clearer picture. Optimally, we find a package that can give us page information. Not sure if that is possible in these data formats though.

### Value and/or benefit

Users with corporate documents will have a lower barrier of entry. Requested in https://github.com/Quansight/ragna/issues/224#issuecomment-1838864057.

### Anything else?

_No response_

### Additional contract requirements

- This task requires support for `.docx` documents. Legacy `.doc` documents are out of scope.
- The document handler must be registered for the `.docx` suffix and importable as `ragna.core.DocxDocumentHandler`.
- `DocxDocumentHandler.extract_pages` yields one `Page` per non-empty paragraph, with the paragraph text in the `text` attribute.
