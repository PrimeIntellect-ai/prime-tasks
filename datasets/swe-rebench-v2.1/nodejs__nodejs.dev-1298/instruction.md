Trademark policy page
## Summary

Create a /trademark policy page with the same content as https://nodejs.org/en/about/trademark/

### Additional contract requirements

- The Footer’s “Trademark Policy” link must point to `/trademark`.
- The `/trademark` page is provided by a default-exported React component in `src/pages/trademark.tsx` that accepts a `data` prop of type `Page` (from `src/types`) and returns a JSX element.
- The trademark policy content is stored in `content/about/trademark.md`.
- The “Edit this page” link on the trademark page must use `https://github.com/nodejs/nodejs.dev/edit/master/content/about/trademark.md`.
