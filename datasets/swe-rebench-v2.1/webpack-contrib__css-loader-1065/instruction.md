modules.mode callback function
<!--
  Issues are so 🔥

  If you remove or skip this template, you'll make the 🐼 sad and the mighty god
  of Github will appear and pile-drive the close button from a great height
  while making animal noises.

  👉🏽 Need support, advice, or help? Don't open an issue!
  Head to StackOverflow or https://gitter.im/webpack/webpack.
-->

- Operating System: Ubuntu 18.04
- Node Version: v13.11.0
- NPM Version: 6.13.7
- webpack Version: 4.42.1
- css-loader Version: 3.4.2

### Feature Proposal

[`modules.mode`](https://github.com/webpack-contrib/css-loader#mode) can be set to `global` or `local` (AFAICT) -- I propose allowing it to take a callback function as well. Callback will be given the full filepath/name which can then return a string, "global" or "local".

### Feature Use Case

Projects that were started with existing CSS files will likely need to use "global" mode to avoid having to refactor everything/wrap every file. However, new files/components will probably want to use "local" mode. Being able to turn global/local on for specific directories will make this much easier.

**Edit:** I suppose if [this](https://github.com/webpack/webpack/issues/8952) gets fixed, that'd work too.
