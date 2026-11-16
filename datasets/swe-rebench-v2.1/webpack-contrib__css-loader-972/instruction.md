Behaviour of the "[path]" placeholder have been changed in a refactor commit
<!--
  Issues are so 🔥

  If you remove or skip this template, you'll make the 🐼 sad and the mighty god
  of Github will appear and pile-drive the close button from a great height
  while making animal noises.

  👉🏽 Need support, advice, or help? Don't open an issue!
  Head to StackOverflow or https://gitter.im/webpack/webpack.
-->

- Operating System:
- Node Version:
- NPM Version:
- webpack Version:
- css-loader Version: 3.0+

### Expected Behavior
`[path]` placeholder gives `path-to-file`
<!-- Remove this section if not reporting a bug or modification request. -->

### Actual Behavior
`[path]` placeholder gives `path/to/file`
<!-- Remove this section if not reporting a bug or modification request. -->

### How Do We Reproduce?
Should be very clear in this commit. https://github.com/webpack-contrib/css-loader/pull/920
`normalizeIdentifier` is removed.
<!--
  Remove this section if not reporting a bug.

  If your webpack config is over 50 lines long, please provide a URL to a repo
  for your beefy 🍖 app that we can use to reproduce.
-->
