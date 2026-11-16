Support for CSS GCPM ‘page groups’
When formatting books for printing, we need to be able to use different margin box content on the first page of each chapter. (In my case, specifically, empty margin boxes to suppress the page numbers and titles which are shown on other pages.)

Prince supports this via the `:first` pseudo-class on named pages (eg `@page chapter:first`), however WeasyPrint does not support this and I believe in this respect Prince is in  fact not compliant with [the spec](https://drafts.csswg.org/css-page/#first-pseudo), since `:first` is (sadly) only intended to match on the first page of a document, not on the first page of a group  of  named pages.

The spec-compliant way to achieve this seems to be with CSS-GCPM’s ‘[page groups](https://drafts.csswg.org/css-gcpm/#document-sequence-selectors)’, eg `@page:nth(1 of chapter)`.
It would be great to see support for this in WeasyPrint!

### Additional contract requirements

Provide a public `PageType` named tuple in module `weasyprint.layout.page` with fields `side`, `blank`, `name`, `index` and `group_index`. `index` is the zero-based absolute page number within the document, and `group_index` is the zero-based index of the page within its named-page group (used for `:nth(... of name)` selectors).
