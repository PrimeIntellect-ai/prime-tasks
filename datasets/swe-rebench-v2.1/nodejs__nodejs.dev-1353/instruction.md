Releases page
## Summary
Create a /release page that has the same content as https://github.com/nodejs/nodejs.org/edit/master/locale/en/about/releases.md

The table data should load from https://github.com/nodejs/Release/blob/main/schedule.json

## Related issue
https://github.com/nodejs/nodejs.dev/issues/1339

### Additional contract requirements

- The releases content is a Markdown document stored at `content/about/releases.md`. Its frontmatter declares `title: Releases`, and its body describes Current and LTS releases and references `schedule.svg`.
- The `/release` path in the upstream request is a typo; serve the page at `/releases`, with its page component located at `src/pages/releases.tsx`.
