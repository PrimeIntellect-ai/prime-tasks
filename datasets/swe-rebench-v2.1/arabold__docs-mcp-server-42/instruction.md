Bug: HtmlProcessor fails to extract title when <title> tag has attributes
## Issue
The current implementation in `src/scraper/processor/HtmlProcessor.ts` uses a simple regex to extract page titles which fails when the `<title>` tag contains attributes.

## Current Implementation
```typescript
const titleMatch = htmlContent.match(/<title>([^<]+)</title>/i);
const title = titleMatch?.[1] || "Untitled";
```

## Problem
This regex pattern fails to extract titles from HTML where the `<title>` tag includes attributes. For example:
```html
<title lang="en">Example Page</title>
```

## Impact
When scraping documentation pages that use attributes in their `<title>` tags (e.g., for language specification), the processor fails to extract the proper title and falls back to "Untitled".

## Proposed Solution
[HIDDEN]

```typescript
[HIDDEN]
// ...
[HIDDEN]
```

This approach would be more robust as it properly handles HTML parsing and automatically accounts for any attributes in the title tag.

### Additional contract requirements

- `HtmlProcessor` must return the title text when the HTML `<title>` element has attributes, rather than falling back to `"Untitled"`.
- If there is no usable page title, `HtmlProcessor` must return `"Untitled"`.
