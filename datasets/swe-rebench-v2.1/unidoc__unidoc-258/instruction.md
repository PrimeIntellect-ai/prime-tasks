Make PDF creator output predictable
When working on https://github.com/unidoc/unidoc/issues/118 I noticed that the size of the document fluctuates noticeably. This means that an output of the library is not predictable and it will generate different document given the same input.

This might be a problem for automated pipelines that involve hashing the generated document.
