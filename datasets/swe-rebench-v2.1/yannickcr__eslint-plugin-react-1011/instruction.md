False positive with display-name rule
Seems like this: `document.createElement` makes the rule believe you're using `React.createElement`:

https://dxr.mozilla.org/mozilla-central/source/devtools/client/webconsole/new-console-output/test/fixtures/serviceContainer.js#16
