direct write document.title does not work
**Describe the bug**
I use `document.title = 'title'`, but this does not work.

**To Reproduce**
Steps to reproduce the behavior:
1. open https://stackblitz.com/edit/node-jyhhtp?file=package.json,index.mjs
2. run `node index.mjs`

**Expected behavior**
described in the link above.

**Device:**
 - nodejs v16.14.2

### Additional contract requirements

- `Document.title` is a public property. Reading it returns the current document title as a string; writing it accepts a string and sets the document title.
- Reading `Document.title` returns the text content of the first `<title>` element in the document.
- Writing `Document.title` updates the text content of the existing `<title>` element. If the document has no `<title>` element, writing creates a `<title>` element with the given text content and appends it to the document's `<head>`.
