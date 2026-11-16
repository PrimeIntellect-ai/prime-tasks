Less strict `merge-pdfs`
## Expected Behavior
I have a couple of `input-streams` containing PDFs that I want to merge into an `output-stream`.

The current `merge-pdfs` function requires that all [inputs are files](https://github.com/dotemacs/pdfboxing/blob/ac810b22aafc32412b6450ef6b7be251ffad53e0/src/pdfboxing/merge.clj#L40), but PDFBox supports [adding `InputStreams`](https://pdfbox.apache.org/docs/2.0.1/javadocs/org/apache/pdfbox/multipdf/PDFMergerUtility.html#addSource(java.io.InputStream)).

Same with the output, `merge-pdfs` requires that the [output is a filename](https://github.com/dotemacs/pdfboxing/blob/ac810b22aafc32412b6450ef6b7be251ffad53e0/src/pdfboxing/merge.clj#L41), but PDFBox supports both [filenames](https://pdfbox.apache.org/docs/2.0.1/javadocs/org/apache/pdfbox/multipdf/PDFMergerUtility.html#setDestinationFileName(java.lang.String)) and [`OutputStreams`](https://pdfbox.apache.org/docs/2.0.1/javadocs/org/apache/pdfbox/multipdf/PDFMergerUtility.html#setDestinationStream(java.io.OutputStream)).

## Potential Solution

To solve this in my codebase I've updated `merge-pdfs` to be less strict:
[HIDDEN]

But I wanted your feedback before submitting a PR.
Is this something you'd be interested in?

### Additional contract requirements

- `merge-pdfs` must accept PDF `InputStream` values as sources and merge their contents.
- It must accept an `OutputStream` destination and write the merged PDF to it.
- The existing workflow using file inputs and a filename destination must continue to work.
