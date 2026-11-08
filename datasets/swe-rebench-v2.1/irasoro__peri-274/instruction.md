Add link to github page
Add a link to the GitHub page to the bottom of the menu page

### Additional contract requirements

- The menu page contains, at its bottom, a link labelled "We are on GitHub" that opens the project's GitHub page.
- `src/data/AppVersion.ts` exports a public constant `homepageURL` holding the project's GitHub page URL.
- `src/data/AppVersion.ts` exports a public function `openGitHubPage()` that opens the project's GitHub page. On the desktop platform it opens the page in a new tab (target `_blank`); on any other platform it opens the page with target `_system` and the feature string `location=yes`.
